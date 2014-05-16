#!/bin/perl

# epi_token.pl - Does the auto give of tokens every $interval,
#                1 token for non-subscribers, 2 tokens for subscribers.
#                Checks if a stream is online or offline every 5 minutes
#                and updates the Database with the status.
#                Tracks the IRC part/join messages to keep track of who is watching.

use strict;
use warnings;
use Config::Simple;
use POE;
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::Connector;
use DBI;
use Log::Log4perl;
use Log::Log4perl::Level;
use LWP::Simple qw(!head);
use LWP::UserAgent;
use JSON;
use Time::HiRes qw(time);
use DateTime;
use DateTime::Duration;
use DateTime::Format::MySQL;
use DateTime::Format::DateParse;
use Time::Piece;
use Time::Piece::MySQL;
use Data::Dumper;
use Scalar::Util 'blessed';
use FileHandle;

use constant {
     true	=> 1,
     false	=> 0,
};

my $cfg = new Config::Simple('/opt/evepriceinfo/epi.conf'); 
my $DBName = $cfg->param("DBName");
my $DBUser = $cfg->param("DBUser");
my $DBPassword = $cfg->param("DBPassword");

my $dbh = DBI->connect("DBI:mysql:database=$DBName;host=localhost",
                         "$DBUser", "$DBPassword",
                         {'RaiseError' => 1});
$dbh->{mysql_auto_reconnect} = 1;
my $sth = $dbh->prepare('SELECT * FROM epi_configuration');
$sth->execute;
my $ref = $sth->fetchall_hashref('setting');
my $twitch_user = $ref->{'twitch_user'}->{'value'};
my $twitch_pwd = $ref->{'twitch_pwd'}->{'value'};
my $twitch_svr = $ref->{'twitch_svr'}->{'value'};
my $twitch_port = $ref->{'twitch_port'}->{'value'};
#my $debug = $ref->{'debug'}->{'value'};
my $debug = 1;
my @channels = $ref->{'channel'}->{'value'};
my $tw_following = $ref->{'tw_following'}->{'value'};
my $tw_online = $ref->{'twitch_online_url'}->{'value'};
my $tw_follow = $ref->{'tw_follow'}->{'value'};
my $tw_pwd = $ref->{'tw_pwd'}->{'value'};;
my $interval = $ref->{'interval'}->{'value'};
my $online_interval = $ref->{'online_interval'}->{'value'};
my $install_dir = $ref->{'install_dir'}->{'value'};
my $token_exclude = $ref->{'token_exclude'}->{'value'};
my $token_give = $ref->{'token_give'}->{'value'};
my $log_conf = $install_dir.$ref->{'log_conf'}->{'value'};

$sth->finish;

Log::Log4perl::Logger::create_custom_level("TOKEN", "WARN");
Log::Log4perl::init_and_watch($log_conf,60);
my $logger = Log::Log4perl->get_logger;

my $offline_timer = 1;

$sth = $dbh->prepare('TRUNCATE rushlock_online_viewers');
$sth->execute;
$sth->finish;

my $irc = POE::Component::IRC::State->spawn(
        Nick   => $twitch_user,
        Server => $twitch_svr,
        Port => $twitch_port,
        Username => $twitch_user,
        Password => $twitch_pwd,
        Debug => $debug,
) or die "Error: $!";

POE::Session->create(
        package_states => [
                main => [ qw(_start tick check irc_part irc_join irc_public irc_353 irc_001) ],
        ],
);

$poe_kernel->run();
 
sub _start {
     $logger->info("epi_token.pl starting!");
     $logger->token("epi_token.pl starting!");
     my ($kernel, $heap) = @_[KERNEL ,HEAP];
     $heap->{connector} = POE::Component::IRC::Plugin::Connector->new();
     $irc->plugin_add('Connector' => $heap->{connector} );
     $heap->{next_alarm_time} = int(time()) + $interval;
     $kernel->alarm(tick => $heap->{next_alarm_time});
     $heap->{next_online_check} = int(time()) + $online_interval;
     $kernel->alarm_add(check => $heap->{next_online_check});
     $irc->yield(register => qw(all));
     $irc->yield(connect => { } );
     return;
}

sub check {
     my ($kernel,$heap) = @_[KERNEL,HEAP];
     $heap->{next_online_check}=int(time())+$online_interval;
     $kernel->alarm(check => $heap->{next_online_check});
     &tw_stream_online($_) for @channels;
}

sub tick {
     my ($kernel,$heap) = @_[KERNEL,HEAP];
     $heap->{next_alarm_time}=int(time())+$interval;
     $kernel->alarm(tick => $heap->{next_alarm_time});
     $logger->debug("timer tick");
     if (&tw_stream_online("\#rushlock")) {
          $logger->debug("Online Tick");
#          &online_token_time("\#rushlock");
     } else {
          $logger->debug("Offline Tick number:$offline_timer");
          if ($offline_timer > 3) {
               $offline_timer = 0;
#               &offline_token_time("\#rushlock");
          }
          $offline_timer = $offline_timer + 1;
     }
     return;
}

sub offline_token_time {
     my $where = $_[0];
     $logger->info("Offline token grant starting.");
     my $sth = $dbh->prepare('SELECT a1.TwitchID, a1.Tokens, a1.TTL from `followers` a1, `rushlock_online_viewers` b1 WHERE a1.TwitchID = b1.TwitchID');
     $sth->execute() or die "Error: ".$sth->errstr;
     my $row =$sth->fetchall_arrayref();
     $sth->finish;
     foreach ( @$row ) {
          next if $_->[0] =~ m/$token_exclude/i;
          $sth = $dbh->prepare('SELECT TwitchID, Tokens, TTL FROM followers WHERE TwitchID LIKE ?');
          $sth->execute($_->[0]);
          my @row2=$sth->fetchrow_array();
          my ($twitchid, $tokens, $ttl) = @row2;
          $sth->finish;
          my $dt1 = DateTime::Format::MySQL->parse_datetime($ttl);
          my $dt2 = DateTime->now(time_zone=>'local');
          my $hours = ($dt2 - $dt1)->hours;
          my $mins = ($dt2 - $dt1)->minutes;
          my $secs = ($dt2 - $dt1)->seconds;
          my $duration = ($hours * 3600) + ($mins * 60) + $secs;
          if ($duration > 3000 && $duration < 4200) {
               $logger->info("Giving a token to $twitchid");
               $tokens = $tokens + 1;
               $sth = $dbh->prepare('UPDATE followers SET Tokens = ?, TTL = NULL WHERE TwitchID like ?');
               $sth->execute($tokens,$twitchid) or die "Error: ".$sth->errstr;
               $sth->finish;
          } else {
               $logger->info("$twitchid didn't get a token. Duration: $duration");
               $sth = $dbh->prepare('UPDATE followers SET TTL = NULL WHERE TwitchID like ?');
               $sth->execute($twitchid) or die "Error: ".$sth->errstr;
               $sth->finish;
          }
     }
     $logger->info("Offline token grant finished.");;
     return;
}

sub online_token_time {
     my $where = $_[0];
     my $sth = $dbh->prepare('SELECT a1.TwitchID, a1.Tokens, a1.TTL from `followers` a1, `rushlock_online_viewers` b1 WHERE a1.TwitchID = b1.TwitchID');
     $sth->execute() or die "Error: ".$sth->errstr;
     my @row;
     my %updates;
     $logger->info("Online token grant starting.");
     while ( @row = $sth->fetchrow_array() ) {
          my ($twitchid, $tokens, $ttl) = @row;
          next if $twitchid =~ m/$token_exclude/i;
          my $dt1 = DateTime::Format::MySQL->parse_datetime($ttl);
          my $dt2 = DateTime->now(time_zone=>'local');
          my $mins = ($dt2 - $dt1)->minutes;
          my $secs = ($dt2 - $dt1)->seconds;
          my $duration = ($mins * 60) + $secs;
          if ($duration > ($interval - 60) && $duration < ($interval + 60)) {
               if (&tw_is_subscriber($twitchid)) {
                    $logger->info("Giving 2 tokens to $twitchid.");
                    $updates{$twitchid}=$tokens+2;
               } else {
                    $logger->info("Giving a token to $twitchid.");;
                    $updates{$twitchid}=$tokens+1;
               }
          } else {
               $logger->info("$twitchid didn't get a token. Duration: $duration");
               $updates{$twitchid}=$tokens;
          }
     }
     $logger->info("Online token grant ended.");
     $sth->finish;
     $sth = $dbh->prepare('UPDATE followers SET Tokens = ?, TTL = NULL WHERE TwitchID like ?');
     while( my ($user,$updatetokens) = each %updates ) {
          $sth->execute($updatetokens,$user);
     }
     $sth->finish;
     return;
}

sub irc_join {
     my $nick = (split /!/, $_[ARG0])[0];
     $logger->debug("$nick has joined the channel.");
     my $sth = $dbh->prepare('INSERT IGNORE INTO rushlock_online_viewers SET TwitchID = ?');
     $sth->execute($nick);
     $sth->finish;
     $sth = $dbh->prepare('SELECT * FROM followers WHERE TwitchID LIKE ?');
     $sth->execute($nick);
     my $ref = $sth->fetchrow_hashref();
     if (!$ref) {
          $logger->debug("$nick not in followers table.");
          $sth = $dbh->prepare('INSERT INTO followers SET TwitchID = ?, Tokens = 0');
          $sth->execute($nick);
          $sth->finish;
     } else {
          $logger->debug("$nick in followers table.");
     }
}

sub irc_part {
     my $nick = (split /!/, $_[ARG0])[0];
     $logger->debug("$nick has left the channel.");
     my $sth = $dbh->prepare('DELETE FROM rushlock_online_viewers WHERE TwitchID = ?');
     $sth->execute($nick);
}

sub irc_public {
     my $nick = (split /!/, $_[ARG0])[0];
     my $msg = $_[ARG2];
     if ($nick =~ m/twitchnotify/ && $msg =~ m/just subscribed/) {
          my @subuser = split(' ',$msg);
          $irc->yield(privmsg => $_, "/me - New Subscriber: $subuser[0]. Welcome to the channel.") for @channels;
          my $sth = $dbh->prepare('INSERT INTO Rushlock_TwitchSubs SET TwitchName = ?, SubDate = ?');
          my $subdate = Time::Piece->new->strftime('%Y-%m-%d');
          $sth->execute($subuser[0],$subdate);
          $sth->finish;
          $logger->info("$subuser[0] subscribed to the channel.");
     }
}

sub irc_353 {
     my $line = $_[ARG1];
     $line =~ s/^\= \#rushlock //g;
     $line =~ s/\@//g;
     $line =~ s/^\://g;
     my @names = split(" ",$line);
     foreach my $user (@names) {
          my $sth = $dbh->prepare('INSERT IGNORE INTO rushlock_online_viewers SET TwitchID = ?');
          $sth->execute($user);
     }
     return;
}
 
sub irc_001 {
     $irc->yield(join => $_) for @channels;
     $irc->yield(privmsg => $_, '/color blue') for @channels;
     return;
}

sub tw_stream_online {
     my $stream = $_[0];
     $stream =~ s/#//g;
     my $sth = $dbh->prepare('UPDATE channel_status SET Status=? WHERE Channel like ?');
     my $ua = LWP::UserAgent->new;
     my $url = $tw_online.$stream;
     my $live = $ua->get($url,"Accept"=>"application/vnd.twitchtv.v2+json","Authorization"=>"$tw_pwd");
     my $code = $live->code();
     if ($code =~ /^5/) {
          $sth->execute('Unknown',$stream);
          $logger->debug("Stream $stream in Unknown state.");
          return false;
     }
     my $decode = decode_json( $live->content );
     if ($decode->{'stream'}) {
          $sth->execute('Online',$stream);
          $logger->debug("Stream $stream is Online.");
          return true;
     } else {
          $sth->execute('Offline',$stream);
          $logger->debug("Stream $stream is Offline state.");
          return false;
     }
}

sub tw_user_follow {
     my $url = $tw_follow;
     $url =~ s/USER/$_[0]/g;
     my $ua = LWP::UserAgent->new;
     my $live = $ua->get($url,"Accept"=>"application/vnd.twitchtv.v2+json","Authorization"=>"$tw_pwd");
     my $code = $live->code();
     if ($code =~ /^5/) { return 0; }
     if ( $live->status_line =~ "404" ) {
        return 1;
     } else {
        return 0;
     }
}

sub tw_is_subscriber {
     $logger->debug("Checking $_[0] to see if they are a subscriber.");
     my $sth = $dbh->prepare('SELECT TwitchName FROM Rushlock_TwitchSubs WHERE TwitchName LIKE ?');
     $sth->execute($_[0]);
     my @ref = $sth->fetchrow_array();
     if ($sth->rows == 0) {
          $logger->debug("$_[0] is not a subscriber.");
          return 0;
     } else {
          $logger->debug("$_[0] is a subscriber.");
          return 1;
     }
}
