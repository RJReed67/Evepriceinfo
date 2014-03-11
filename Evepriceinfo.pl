#!/bin/perl

use strict;
use warnings;
use Config::Simple;
use POE qw( Loop::AnyEvent );
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::BotCommand;
use POE::Component::IRC::Plugin::Connector;
use POE::Component::IRC::Plugin::Proxy;
use POE::Component::IRC::Plugin::Logger;
use DBI;
use Locale::Currency::Format;
use XML::LibXML;
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
use AnyEvent::Twitter::Stream;
use Net::Twitter::Lite::WithAPIv1_1;
use Scalar::Util 'blessed';
use FileHandle;
use POE::Component::Server::HTTP;
use HTTP::Status;
use CGI qw(:standard);

use constant {
     true	=> 1,
     false	=> 0,
};
 
currency_set('USD','#,###.## ISK',FMT_COMMON);

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
my $debug = $ref->{'debug'}->{'value'};
my $tw_following = $ref->{'tw_following'}->{'value'};
my $tw_follow = $ref->{'tw_follow'}->{'value'};
my $tw_pwd = $ref->{'tw_pwd'}->{'value'};;
my $interval = $ref->{'interval'}->{'value'};
my $install_dir = $ref->{'install_dir'}->{'value'};
my $log_dir = $install_dir.$ref->{'log_dir'}->{'value'};
my @channels = ($ref->{'channel'}->{'value'});
my $log_token = $ref->{'log_token'}->{'value'};
my $bindport = $ref->{'console_bindport'}->{'value'};
my $token_exclude = $ref->{'token_exclude'}->{'value'};
my $consumer_key = $ref->{'tw_consumer_key'}->{'value'};
my $consumer_secret = $ref->{'tw_consumer_secret'}->{'value'};
my $tw_token = $ref->{'tw_token'}->{'value'};
my $tw_token_secret = $ref->{'tw_token_secret'}->{'value'};
my $log_chat = $ref->{'log_chat'}->{'value'};
my $token_give = $ref->{'token_give'}->{'value'};
$sth->finish;

my $token_log = $log_dir."/token-log.txt";
my $console_log = $log_dir."/console-log.txt";
my $error_log = $log_dir."/error-log.txt";
my $offline_timer = 0;

my $giveaway_key = 0;
my $giveaway_open = -1;
my $giveaway_title = "";
my $giveaway_threshold = 0;
my $giveaway_autogive = 0;
$sth = $dbh->prepare('SELECT COUNT(*) FROM giveaway');
$sth->execute;
my ($count) = $sth->fetchrow_array;
$sth->finish;
if ($count == 0) {
     $giveaway_key = 0;
     $giveaway_open = -1;
     $giveaway_title = "";
     $giveaway_threshold = 0;
     $giveaway_autogive = 0;
} else {
     $sth = $dbh->prepare('SELECT * FROM giveaway ORDER BY GiveKey DESC LIMIT 1');
     $sth->execute;
     $ref = $sth->fetchrow_hashref();
     if ($ref->{'EndDate'} eq "0000-00-00 00:00:00" ) {
          $giveaway_key = $ref->{'GiveKey'};
          $giveaway_open = 1;
          $giveaway_title = $ref->{'GiveTitle'};
          $giveaway_threshold = $ref->{'Threshold'};
          $giveaway_autogive = $ref->{'AutoGive'};
     } else {
          $giveaway_key = 0;
          $giveaway_open = -1;
          $giveaway_title = "";
          $giveaway_threshold = 0;
          $giveaway_autogive = 0;
     }
}

my $tlog;
my $clog;
my $elog;
my $stdout;
my $stderr;
if ($log_token == 1) {
     $tlog = FileHandle->new(">> $token_log");
     $tlog->autoflush(1);
}
if ($debug == 1) {
     $clog = FileHandle->new("+> $console_log");
     $clog->autoflush(1);
}
open($elog, ">>","$error_log");
$stdout = *STDOUT;
$stderr = *STDERR;
*STDERR = $elog;
*STDOUT = $clog if $debug == 1;
 
my @cmds = ();
my %help = ();

push(@cmds,'irc_botcmd_info');
$sth = $dbh->prepare('SELECT * FROM epi_commands');
$sth->execute;
$ref = $sth->fetchall_hashref('CmdKey');
foreach ( keys %$ref ) {
     if ($ref->{$_}->{'CmdType'} eq 'internal') {
          push(@cmds,$ref->{$_}->{'Command'});
     } elsif ($ref->{$_}->{'CmdType'} eq 'info') {
          my $key = $ref->{$_}->{'Command'};
          my $helptxt = $ref->{$_}->{'HelpInfo'};
          $help{$key}{info}="$helptxt";
          $help{$key}{handler}="irc_botcmd_info";
     } else {
          push(@cmds,"irc_botcmd_".$ref->{$_}->{'Command'});
          $help{$ref->{$_}->{'Command'}}=$ref->{$_}->{'HelpInfo'};
     }
}
$sth->finish;

$sth = $dbh->prepare('TRUNCATE rushlock_online_viewers');
$sth->execute;
$sth->finish;
$sth = $dbh->prepare('TRUNCATE killcache');
$sth->execute;
$sth->finish;

my $httpd = POE::Component::Server::HTTP->new(
     Port => 8000,
     ContentHandler => {
          '/'      => \&handler,
     },
     Headers => { Server => 'EvePriceInfo' },
);

sub handler {
     my ($kernel, $heap) = @_[KERNEL ,HEAP];
     my ($request, $response) = @_;
     $response->code(RC_OK);
     my $q;
     if ($request->method() eq 'POST') {
          $q = new CGI($request->content);
     } else {
          $request->uri() =~ /\?(.+$)/;
          if (defined($1)) {
               $q = new CGI($1);
          } else {
               $q = new CGI;
          }
     }
     my $content = start_html("EvePriceInfo Command");
     if ($request->method() eq 'POST') {
          for ($q->param("cmd")) {
               if (/^!token /) { $content .= "token".br() }
               if (/^!plex /) { $content .= "plex".br() }
               if (/^!pc /) { $content .= "pc".br() }
               if (/^!pca /) { $content .= "pca".br() }
               if (/^!hpc /) { $content .= "hpc".br() }
               if (/^!rpc /) { $content .= "rpc".br() }
               if (/^!ice /) { $content .= "ice".br() }
               if (/^!news/) { $content .= "news".br() }
               if (/^!yield /) { $content .= "yield".br() }
               if (/^!zkb /) { $content .= "zkb".br() }
          }
     }
     $content .= start_form(
     -method  => "post",
     -action  => "/",
     -enctype => "applications/x-www-form-urlencoded",
     )
     . "EvePriceInfo Cmd: "
     . textfield("cmd")
     . br()
     . submit("submit", "submit")
     . end_form()
     . end_html();
     $response->content($content);
     return RC_OK;
}

my $nt = Net::Twitter::Lite::WithAPIv1_1->new(
     consumer_key    => $consumer_key,
     consumer_secret => $consumer_secret,
     token           => $tw_token,
     token_secret    => $tw_token_secret,
     ssl             => 1,
);

#POE::Kernel->run(); # silence the warning

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
                main => [ @cmds ],
        ],
);

my $done = AnyEvent->condvar;

my $listener = AnyEvent::Twitter::Stream->new(
    consumer_key    => $consumer_key,
    consumer_secret => $consumer_secret,
    token           => $tw_token,
    token_secret    => $tw_token_secret,
    method          => "userstream",
    api_url         => "https://userstream.twitter.com/1.1/user.json",
    timeout         => 300,
    on_tweet        => sub { 
       my $tweet = shift;
       if ($tweet->{text}) {
          $irc->yield(privmsg => $_, "Tweet from \@$tweet->{user}{screen_name}: $tweet->{text}") for @channels;
       }
    },
    on_error        => sub {
       my $error = shift;
       warn($error);
       $done->send;
    },
);

my $listener2 = AnyEvent::Twitter::Stream->new(
    consumer_key    => $consumer_key,
    consumer_secret => $consumer_secret,
    token           => $tw_token,
    token_secret    => $tw_token_secret,
    method          => "filter",
    track           => "#Rushlock",
    api_url         => "https://userstream.twitter.com/1.1/user.json",
    timeout         => 300,
    on_tweet        => sub { 
       my $tweet = shift;
       if ($tweet->{text}) {
           my $logtime = Time::Piece->new->strftime('%m/%d/%Y %H:%M:%S');
           my $sth = $dbh->prepare('SELECT a.TwitchID, a.Tokens, b.TTL FROM `followers` a LEFT JOIN `TwitterID2TwitchID` b ON a.TwitchID = b.TwitchID WHERE b.TwitterID IS NOT NULL AND b.TwitterID like ?');
           my $id = "\@".$tweet->{user}{screen_name};
           print $clog "$logtime: Got a tweet from $id.\n" if $debug==1;
           $sth->execute($id) or die "Error: ".$sth->errstr;
           my $rows = $sth->rows;
           if ($rows > 0) {
                my @row=$sth->fetchrow_array();
                my ($twitchid,$tokens,$ttl) = @row;
                print $clog "Twitter user: $id is $twitchid.\n" if $debug==1;
                $sth->finish;
                return if $twitchid =~ m/$token_exclude/i;
                my $dt1 = DateTime::Format::MySQL->parse_datetime($ttl);
                my $dt2 = DateTime->now(time_zone=>'local');
                my $days = ($dt2 - $dt1)->days;
                my $hours = ($dt2 - $dt1)->hours;
                my $duration = ($days * 24) + $hours;
                if ($duration > 18) {
                     print $tlog "$logtime: Giving 5 tokens to \"$twitchid\" for tweeting.\n" if $log_token==1;
                     $tokens = $tokens + 5;
                     $sth = $dbh->prepare('UPDATE followers SET Tokens = ? WHERE TwitchID like ?');
                     $sth->execute($tokens,$twitchid) or die "Error: ".$sth->errstr;
                     $sth->finish;
                     $sth = $dbh->prepare('UPDATE TwitterID2TwitchID SET TTL = NULL WHERE TwitchID like ?');
                     $sth->execute($twitchid) or die "Error: ".$sth->errstr;
                     if ($debug==1) {
                          $irc->yield(privmsg => $_, "5 Tokens given to $twitchid for tweet: $tweet->{text}") for @channels;
                     }
                } else {
                     if ($debug==1) {
                          $irc->yield(privmsg => $_, "Tokens not given to $twitchid for tweet, only $hours hours since last tweet") for @channels;
                     }
                } 
           }
       }
    },
    on_error        => sub {
       my $error = shift;
       warn($error);
       $done->send;
    },
);

my $responder = AnyEvent::Twitter::Stream->new(
    consumer_key    => $consumer_key,
    consumer_secret => $consumer_secret,
    token           => $tw_token,
    token_secret    => $tw_token_secret,
    method          => "filter",
    track           => "#CostOfPLEX",
    api_url         => "https://userstream.twitter.com/1.1/user.json",
    timeout         => 300,
    on_tweet        => sub { 
       my $tweet = shift;
       if ($tweet->{text}) {
           my $screen_name = $tweet->{user}{screen_name};
           my $logtime = Time::Piece->new->strftime('%m/%d/%Y %H:%M:%S');
           print $clog "$logtime: Got a tweet from $screen_name.\n" if $debug==1;
           my $id = $tweet->{user}{id};
           my %hubs = ("Jita",30000142,"Hek",30002053,"Rens",30002510,"Amarr",30002187,"Dodixie",30002659);
           my $price="Market Hub Plex Prices - ";
           while ((my $sysname, my $sysid) = each (%hubs)) {
               $price = $price.$sysname.":".currency_format('USD', &GetXMLValue($sysid,29668,"//sell/min"), FMT_COMMON)." ";
           }
           my $result = eval { $nt->new_direct_message({ text => $price , screen_name => $screen_name }) };
           if ( my $err = $@ ) {
               die $@ unless blessed $err && $err->isa('Net::Twitter::Lite::Error');
               print $elog "HTTP Response Code: ".$err->code."\n";
               print $elog "HTTP Message......: ".$err->message."\n";
               print $elog "Twitter error.....: ".$err->error."\n";
           }
       }
    },
    on_error        => sub {
       my $error = shift;
       warn($error);
       $done->send;
    },
);


$done->recv;

$poe_kernel->run();
 
sub _start {
     my ($kernel, $heap) = @_[KERNEL ,HEAP];
     $heap->{connector} = POE::Component::IRC::Plugin::Connector->new();
     $irc->plugin_add('Connector' => $heap->{connector} );
     $heap->{next_alarm_time} = int(time()) + $interval;
     $kernel->alarm(tick => $heap->{next_alarm_time});
     $irc->plugin_add('Logger' => POE::Component::IRC::Plugin::Logger->new(
          Path     => $log_dir,
          DCC      => 0,
          Private  => 0,
          Public   => $log_chat,
     ));
     $irc->plugin_add('BotCommand', POE::Component::IRC::Plugin::BotCommand->new(
        Addressed => 0,
        Prefix => '!',
        Method => 'privmsg',
        Ignore_unknown => 1,
        Commands => { %help },
     ));
     $irc->yield(register => qw(all));
     $irc->yield(connect => { } );
     return;
}

sub _default {
     return if ($debug != 1);
     my ($event, $args) = @_[ARG0 .. $#_];
     my @output = ( "$event: " );

     for my $arg ( @$args ) {
         if (ref $arg  eq 'ARRAY') {
             push( @output, '[' . join(', ', @$arg ) . ']' );
         }
         else {
             push ( @output, "'$arg'" );
         }
     }
     my $logtime = Time::Piece->new->strftime('%m/%d/%Y %H:%M:%S');
     print $clog $logtime.": ".join ' ', @output, "\n";
     return 0;
}

sub tick {
     my($kernel,$heap) = @_[KERNEL,HEAP];
     my $logtime = Time::Piece->new->strftime('%m/%d/%Y %H:%M:%S');
     $heap->{next_alarm_time}=int(time())+$interval;
     $kernel->alarm(tick => $heap->{next_alarm_time});
     print $clog $logtime." timer!\n" if $debug==1;
     if (&tw_stream_online) {
          $offline_timer = 0;
          &token_time("\#rushlock");
     } else {
          $offline_timer = $offline_timer + 1;
          print $clog "Offline Tick: $offline_timer\n" if $debug==1;
          if ($offline_timer > 3) {
               print $tlog "$logtime: Offline token grant start.\n" if $log_token==1;
               $offline_timer = 0;
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
                         print $tlog "$logtime: Giving a token to \"$twitchid\".\n" if $log_token==1;
                         $tokens = $tokens + 1;
                         $sth = $dbh->prepare('UPDATE followers SET Tokens = ?, TTL = NULL WHERE TwitchID like ?');
                         $sth->execute($tokens,$twitchid) or die "Error: ".$sth->errstr;
                         $sth->finish;
                    } else {
                         print $tlog "$logtime: \"$twitchid\" didn't get a token. Duration: $duration\n" if $log_token==1;
                         $sth = $dbh->prepare('UPDATE followers SET TTL = NULL WHERE TwitchID like ?');
                         $sth->execute($twitchid) or die "Error: ".$sth->errstr;
                         $sth->finish;
                    }
               }
               print $tlog "$logtime: Offline token grant ended.\n" if $log_token==1;
          }
     }
     return;
}

sub token_time {
     my $where = $_[0];
     my $logtime = Time::Piece->new->strftime('%m/%d/%Y %H:%M:%S');
     my $sth = $dbh->prepare('SELECT a1.TwitchID, a1.Tokens, a1.TTL from `followers` a1, `rushlock_online_viewers` b1 WHERE a1.TwitchID = b1.TwitchID');
     $sth->execute() or die "Error: ".$sth->errstr;
     my @row;
     my %updates;
     print $tlog "$logtime: Online token grant starts.\n" if $log_token==1;
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
                    $logtime = Time::Piece->new->strftime('%m/%d/%Y %H:%M:%S');
                    print $tlog "$logtime: Giving 2 tokens to \"$twitchid\".\n" if $log_token==1;
                    $updates{$twitchid}=$tokens+2;
               } else {
                    $logtime = Time::Piece->new->strftime('%m/%d/%Y %H:%M:%S');
                    print $tlog "$logtime: Giving a token to \"$twitchid\".\n" if $log_token==1;
                    $updates{$twitchid}=$tokens+1;
               }
          } else {
               $logtime = Time::Piece->new->strftime('%m/%d/%Y %H:%M:%S');
               print $tlog "$logtime: \"$twitchid\" didn't get a token. Duration: $duration\n" if $log_token==1;
               $updates{$twitchid}=$tokens;
          }
     }
     $logtime = Time::Piece->new->strftime('%m/%d/%Y %H:%M:%S');
     print $tlog "$logtime: Online token grant ended.\n" if $log_token==1;
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
     my $logtime = Time::Piece->new->strftime('%m/%d/%Y %H:%M:%S');
     print $clog "$logtime: $nick has joined the channel.\n" if $debug==1;
     my $sth = $dbh->prepare('INSERT IGNORE INTO rushlock_online_viewers SET TwitchID = ?');
     $sth->execute($nick);
     $sth->finish;
     $sth = $dbh->prepare('SELECT * FROM followers WHERE TwitchID LIKE ?');
     $sth->execute($nick);
     my $ref = $sth->fetchrow_hashref();
     if (!$ref) {
          print $clog "$logtime: $nick not in followers table.\n" if $debug==1;
          $sth = $dbh->prepare('INSERT INTO followers SET TwitchID = ?, Tokens = 0');
          $sth->execute($nick);
          $sth->finish;
          $sth = $dbh->prepare('INSERT INTO Rushlock_WeeklyTokenCount SET TwitchID = ?, Token = 0');
          $sth->execute($nick);
     } else {
          print "$nick in followers table.\n" if $debug==1;
          $sth = $dbh->prepare('UPDATE followers SET TTL = NULL WHERE TwitchID like ?');
          $sth->execute($nick);
          $sth->finish;
          $sth = $dbh->prepare('SELECT * FROM Rushlock_WeeklyTokenCount WHERE TwitchID LIKE ?');
          $sth->execute($nick);
          my $ref2 = $sth->fetchrow_hashref();
          if (!$ref2) {
               print $clog "$logtime: $nick not in weekly token count.\n" if $debug==1;
               $sth->finish;
               $sth = $dbh->prepare('INSERT INTO Rushlock_WeeklyTokenCount SET TwitchID = ?, Token = 0');
               $sth->execute($nick);
          }
     }
}

sub irc_part {
     my $nick = (split /!/, $_[ARG0])[0];
     my $logtime = Time::Piece->new->strftime('%m/%d/%Y %H:%M:%S');
     print $clog "$logtime: $nick has left the channel.\n" if $debug==1;
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
     }
}

sub irc_352 {
     my $user = (split / /,$_[ARG1])[1];
     my $sth = $dbh->prepare('SELECT * FROM rushlock_online_viewers WHERE TwitchID LIKE ?');
     $sth->execute($user);
     my $ref = $sth->fetchrow_hashref();
     if (!$ref) {
          $sth = $dbh->prepare('INSERT INTO rushlock_online_viewers SET TwitchID = ?');
          $sth->execute($user);
     }
     return;
}

sub irc_353 {
     my $line = $_[ARG1];
     $line =~ s/^\= \#rushlock //g;
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

sub irc_botcmd_addtweetid {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $user) = @_[ARG1, ARG2];
     $user =~ s/\s+$//;
     if ( ($user eq "?") || ($user !~ /^@\w+/) ) {
          $irc->yield(privmsg => $where, "/me - Use this command to add your TwitterID to the bot database. Include the @ with your ID.");
     } else {
          my $sth = $dbh->prepare('SELECT * FROM TwitterID2TwitchID WHERE TwitchID LIKE ?');
          $sth->execute($nick) or die "Error: ".$sth->errstr;
          my $ref = $sth->fetchrow_hashref();
          $sth->finish;
          if (!$ref) {
               $sth = $dbh->prepare('INSERT INTO TwitterID2TwitchID SET TwitchID = ?, TwitterID = ?, TTL = NULL');
               $sth->execute($nick,$user) or die "Error: ".$sth->errstr;
               $irc->yield(privmsg => $where, "/me - $nick set to $user.");
          } else {
               $irc->yield(privmsg => $where, "/me - $nick already in database.");
          }
     }
     return;
}

sub irc_botcmd_info {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, 14];
     $arg =~ s/\s+$//;
     my $sth = $dbh->prepare('SELECT * FROM epi_info_cmds WHERE CmdName LIKE ?');
     $sth->execute($arg);
     my $ref = $sth->fetchrow_hashref();
     $irc->yield(privmsg => $where, "/me - ".$ref->{'DisplayInfo'});
     return;
}

sub irc_botcmd_add {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     $arg =~ s/\s+$// if $arg ne '';
     my ($change, $user) = split(' ', $arg, 2);
     if ($irc->is_channel_operator($where,$nick)) {
          my $sth;
          if ($giveaway_autogive == 1 && $giveaway_open != 1 && $user eq "evepriceinfo") {
               $sth = $dbh->prepare('SELECT Winner FROM giveaway WHERE AutoGive = 1 ORDER BY GiveKey LIMIT 1');
               $sth->execute;
               ($user) = $sth->fetchrow_array;
               $sth->finish;
          }
          $sth = $dbh->prepare('SELECT * FROM followers WHERE TwitchID LIKE ?');
          $sth->execute($user);
          my $ref = $sth->fetchrow_hashref();
          if (!$ref) {
               $irc->yield(privmsg => $where, "/me - User $user not found in token table.");
          } else {
               my $cur_tokens = $ref->{'Tokens'};
               $sth = $dbh->prepare('UPDATE followers SET Tokens = ?, TTL = ?  WHERE TwitchID like ?');
               $cur_tokens = $cur_tokens + $change;
               $sth->execute($cur_tokens,$ref->{'TTL'},$user);
               $irc->yield(privmsg => $where, "/me - $change tokens added to $user\'s balance.");
               $sth->finish;
               $sth = $dbh->prepare('UPDATE giveaway SET AutoGive=0 WHERE GiveKey=?');
               $sth->execute($giveaway_key);
               $giveaway_autogive = 0;
          }
          $sth->finish;
     }
     my $logtime = Time::Piece->new->strftime('%m/%d/%Y %H:%M:%S');
     print $tlog "$logtime: $nick added $change tokens to $user balance\n" if $log_token==1;
     return;
}

sub irc_botcmd_wg500 {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     $arg =~ s/\s+$//;
     if ($irc->is_channel_operator($where,$nick)) {
          if ($arg) {
               $irc->yield(privmsg => $where, "/me - All isk from loot/salvage/ore gathered during the week, will be added to the weekly drawing. 500 Token req to be entered automatically. You do not need to be present to win. Drawing is done on Sunday of each week.");
          } else {
               my $sth = $dbh->prepare('SELECT * FROM followers WHERE Tokens > 499 ORDER BY RAND() LIMIT 1');
               $sth->execute();
               my $ref = $sth->fetchrow_hashref();
               if (!$ref) {
                    $irc->yield(privmsg => $where, "No winner found!");
               } else {
                    my $winner = $ref->{'TwitchID'};
                    my $winner2 = "";
                    if ( &tw_user_follow($winner) == 0 ) {
                       $winner2 = $winner." (follower)";
                    } else {
                       $winner2 = $winner." (not following)";
                    }
                    $sth->finish;
                    $sth = $dbh->prepare('INSERT INTO giveaway SET GiveTitle=?, Threshold=500, AutoGive=?, StartDate=NOW(), EndDate=NOW(), Winner=?');
                    $sth->execute("Weekly Giveaway",0,$winner);
                    $sth->finish;
                    $irc->yield(privmsg => $where, "/me - Congratulations $winner2, you've won this week's giveaway!");
                    $irc->yield(privmsg => $where, "/me - $winner! Come On Down!");
               }
          }
     }
     return;
}

sub irc_botcmd_subgive {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     $arg =~ s/\s+$//;
     if ($irc->is_channel_operator($where,$nick)) {
          if ($arg) {
               $irc->yield(privmsg => $where, "/me - Random draw of current subscribers.");
          } else {
               my $sth = $dbh->prepare('SELECT * FROM Rushlock_TwitchSubs ORDER BY RAND() LIMIT 1');
               $sth->execute();
               my $ref = $sth->fetchrow_hashref();
               if (!$ref) {
                    $irc->yield(privmsg => $where, "/me - No winner found!");
               } else {
                    my $winner = $ref->{'TwitchName'};
                    my $winner2 = "";
                    if ( &tw_user_follow($winner) == 0 ) {
                       $winner2 = $winner." (follower)";
                    } else {
                       $winner2 = $winner." (not following)";
                    }
                    $irc->yield(privmsg => $where, "/me - Congratulations $winner2, you've won this week's Subscriber Giveaway!");
                    $irc->yield(privmsg => $where, "/me - $winner! Come On Down!");
               }
          }
     }
     return;
}

sub irc_botcmd_take {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     $arg =~ s/\s+$//;
     my ($change, $user) = split(' ', $arg, 2);
     if ($irc->is_channel_operator($where,$nick)) {
          my $logtime = Time::Piece->new->strftime('%m/%d/%Y %H:%M:%S');
          print $tlog "$logtime: $nick subtracted $change tokens from $user balance\n" if $log_token==1;
          my $sth = $dbh->prepare('SELECT * FROM followers WHERE TwitchID LIKE ?');
          $sth->execute($user);
          my $ref = $sth->fetchrow_hashref();
          if (!$ref) {
               $irc->yield(privmsg => $where, "/me - User $user not found in token table.");
          } else {
               my $cur_tokens = $ref->{'Tokens'};
               $sth = $dbh->prepare('UPDATE followers SET Tokens = ?, TTL = ? WHERE TwitchID like ?');
               $cur_tokens = $cur_tokens - $change;
               $sth->execute($cur_tokens,$ref->{'TTL'},$user);
               $irc->yield(privmsg => $where, "/me - $change tokens taken from $user\'s balance.");
          }
     }

     return;
}

sub irc_botcmd_token {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     my ($kernel, $self) = @_[KERNEL, OBJECT];
     &onlinecheck($nick);
     if ($arg) {
          if ($irc->is_channel_operator($where,$nick) && $arg ne "?") {
               my $sth = $dbh->prepare('SELECT * FROM followers WHERE TwitchID LIKE ?');
               $sth->execute($arg);
               my $ref = $sth->fetchrow_hashref();
               if (!$ref) {
                    $kernel->yield('say',($where, "User $arg not found in token table."));
               } else {
                    $kernel->yield('say',($where, "$arg has $ref->{'Tokens'} tokens."));
               }
          } else {
               if (&tw_stream_online) {
                    $kernel->yield('say',($where, "Viewers will earn 1 token every 15 minutes in channel while live and 1 token every hour while offline! Giveaways will require, but not take, tokens to enter. Check your token balance AFTER the cast with the !token command"));
               } else {
                    $kernel->yield('say',($where, "Viewers will earn 1 token every 15 minutes in channel while live and 1 token every hour while offline! Giveaways will require, but not take, tokens to enter."));
               }
          }
     } else {
          if (!&tw_stream_online) {
               my $sth = $dbh->prepare('SELECT * FROM followers WHERE TwitchID LIKE ?');
               $sth->execute($nick);
               my $ref = $sth->fetchrow_hashref();
               if (!$ref) {
                    $kernel->yield('say',($where, "User $nick not found in token table."));
               } else {
                    $kernel->yield('say',($where,"$nick has $ref->{'Tokens'} tokens."));
               }
          } elsif ( &tw_is_subscriber($nick) ) {
               my $sth = $dbh->prepare('SELECT * FROM followers WHERE TwitchID LIKE ?');
               $sth->execute($nick);
               my $ref = $sth->fetchrow_hashref();
               if (!$ref) {
                    $kernel->yield('say',($where, "User $nick not found in token table."));
               } else {
                    $kernel->yield('say',($where, "$nick has $ref->{'Tokens'} tokens."));
               }
          } elsif (!&tw_is_subscriber($nick)) {
               my $sth = $dbh->prepare('SELECT * FROM epi_info_cmds WHERE CmdName LIKE ?');
               $sth->execute("sub");
               my $ref = $sth->fetchrow_hashref();
               $kernel->yield('say',($where, "$ref->{'DisplayInfo'}"));
          }
     }
     $sth->finish;
     return;
}

sub irc_botcmd_give {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     if (!$irc->is_channel_operator($where,$nick)) {
          return;
     }
     $arg =~ s/\s+$//;
     my $logtime = Time::Piece->new->strftime('%m/%d/%Y %H:%M:%S');
     print $clog "$logtime: Give function called by: $nick, with Args: $arg\n" if $debug==1;
     if (!$arg) {
          $irc->yield(privmsg => $where, "/me - Not a valid give command. Valid commands are close, draw, history, open # Title, timed #mins #tokenreq Title.");
          return;
     } elsif ($arg =~ /^open/) {
          if ($giveaway_open == 1) {
               $irc->yield(privmsg => $where, "/me - A giveaway is still open. Please close the giveaway before attempting to do a new one.");
               return;
          }
          my $sth = $dbh->prepare('TRUNCATE TABLE entrylist');
          $sth->execute();
          $sth->finish;
          my ($cmd,$threshold,$title) = split(' ',$arg,3);
          $sth = $dbh->prepare('INSERT INTO giveaway SET GiveTitle=?, Threshold=?, AutoGive=?, StartDate=NOW()');
          $sth->execute($title,$threshold,$giveaway_autogive);
          $giveaway_open = 1;
          $giveaway_title = $title;
          $giveaway_threshold = $threshold;
          $sth->finish;
          $sth = $dbh->prepare('SELECT GiveKey FROM giveaway ORDER BY GiveKey DESC LIMIT 1');
          $sth->execute();
          ($giveaway_key) = $sth->fetchrow_array;
          $irc->yield(privmsg => $where, "/me - Drawing for $title, now open. You must have at least $threshold token(s) to enter. Use the !enter command to enter drawing! Good Luck!");
     } elsif ($arg =~ /^timed/) {
          if ($giveaway_open == 1) {
               $irc->yield(privmsg => $where, "/me - A giveaway is still open. Please close the giveaway before attempting to do a new one.");
               return;
          }
          my ($cmd,$mins,$threshold,$title) = split(' ',$arg,4);
          if ($mins < 1 || $mins > 9) {
               $irc->yield(privmsg => $where, "/me - The number of minutes must be between 1 and 9 minutes.");
               return;
          }
          if ($title eq "") {
               $irc->yield(privmsg => $where, "/me - The format must be: timed #min #tokenreq Title of Giveaway.");
               return;
          }
          print $clog "$logtime: Time Giveaway function called by: $nick\n with Args: $arg" if $debug==1;
          my ($kernel, $self) = @_[KERNEL, OBJECT];
          my $sectimer = $mins * 60;
          $_[ARG2]="open $threshold $title";
          $kernel->delay_set(irc_botcmd_give => 1, $_[ARG0],$_[ARG1],$_[ARG2] );
          $kernel->delay_set(say => $sectimer - 60, $_[ARG1],"Only 1 more minute until the giveaway for $title is closed. Get your !enter cmds in now!");
          $kernel->delay_set(say => $sectimer - 10, $_[ARG1],"Only 10 more seconds until the giveaway for $title is closed. Get your !enter cmds in now!");
          $_[ARG2]="close";
          $kernel->delay_set(irc_botcmd_give => $sectimer, $_[ARG0],$_[ARG1],$_[ARG2] );
          $_[ARG2]="draw";
          $kernel->delay_set(irc_botcmd_give => $sectimer + 10, $_[ARG0],$_[ARG1],$_[ARG2] );
     } elsif ($arg =~ /^close/) {
          if ($giveaway_open == 1) {
               my $sth = $dbh->prepare('UPDATE giveaway SET EndDate=NOW() WHERE GiveKey=?');
               $sth->execute($giveaway_key);
               $giveaway_open = -1;
               $irc->yield(privmsg => $where, "/me - Drawing for $giveaway_title, is now closed. No more !enter commands will be accepted.");
          }
     } elsif ($arg =~ /^draw/) {
          if ($giveaway_open == 1) {
               $irc->yield(privmsg => $where, "/me - Giveaway is still open. Please close the giveaway before attempting to draw a winner.");
          } else {
               my $sql = 'SELECT * FROM entrylist';
               my @ref = @{$dbh->selectcol_arrayref($sql)};
               my $count = @ref;
               $irc->yield(privmsg => $where, "/me - There are $count entries in the $giveaway_title.");
               my $winner = $ref[int(rand(0+$count))];
               my $sth = $dbh->prepare('UPDATE giveaway SET Winner=? WHERE GiveKey=?');
               $sth->execute($winner,$giveaway_key);
               my $winner2 = "";
               if ( &tw_user_follow($winner) == 0 ) {
                  $winner2 = $winner." (follower)";
               } else {
                  $winner2 = $winner." (not following)";
               }
               $irc->yield(privmsg => $where, "/me - The winner of $giveaway_title is $winner2! Congratulations!");
               $irc->yield(privmsg => $where, "/me - $winner! Come On Down!");
          }
     } elsif ($arg =~ /^history/) {
          my $sth = $dbh->prepare('SELECT * FROM giveaway ORDER BY GiveKey DESC LIMIT 3');
          $sth->execute;
          $irc->yield(privmsg => $where, "/me - The last 3 winners were:");
          while (my @row = $sth->fetchrow_array) {
               $irc->yield(privmsg => $where, "/me - $row[5] : $row[6], won $row[1].");
          }
     } else {
          $irc->yield(privmsg => $where, "/me - Not a valid give command. Valid commands are close, draw, history, open # Title, timed #mins #tokenreq Title.");
     }
     $sth->finish;
     return;
}

sub irc_botcmd_tgw {
     my $nick = (split /!/, $_[ARG0])[0];
     my $where = $_[ARG1];
     if (!$irc->is_channel_operator($where,$nick)) {
          return;
     }
     if ($giveaway_open == 1) {
          $irc->yield(privmsg => $where, "/me - A giveaway is still open. Please close the giveaway before attempting to do a new one.");
          return;
     }
     my $logtime = Time::Piece->new->strftime('%m/%d/%Y %H:%M:%S');
     print $clog "$logtime: Time Giveaway function called by: $nick\n" if $debug==1;
     my ($kernel, $self) = @_[KERNEL, OBJECT];
     $giveaway_autogive = 1;
     $_[ARG2]="open 1 $token_give Tokens";
     $kernel->delay_set(irc_botcmd_give => 1, $_[ARG0],$_[ARG1],$_[ARG2] );
     $kernel->delay_set(say => 120, $_[ARG1],"Only 1 more minute until the giveaway for $token_give Tokens is closed. Get your !enter cmds in now!");
     $kernel->delay_set(say => 170, $_[ARG1],"Only 10 more seconds until the giveaway for $token_give Tokens is closed. Get your !enter cmds in now!");
     $_[ARG2]="close";
     $kernel->delay_set(irc_botcmd_give => 180, $_[ARG0],$_[ARG1],$_[ARG2] );
     $_[ARG2]="draw";
     $kernel->delay_set(irc_botcmd_give => 190, $_[ARG0],$_[ARG1],$_[ARG2] );
     $_[ARG2]="$token_give evepriceinfo";
     $kernel->delay_set(irc_botcmd_add => 250, $_[ARG0],$_[ARG1],$_[ARG2] );
     return;
}

sub irc_botcmd_t1sgw {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     $arg =~ s/\s+$//;
     if (!$irc->is_channel_operator($where,$nick)) {
          return;
     }
     my $logtime = Time::Piece->new->strftime('%m/%d/%Y %H:%M:%S');
     print $clog "$logtime: Tech 1 ship Giveaway called by $nick with Args: $arg" if $debug == 1;
     my ($kernel, $self) = @_[KERNEL, OBJECT];
     my ($shiptype, $contact) = split(/ /,$arg);
     if ($contact eq '') {
          $contact = "Rushlock";
     }
     if ($shiptype =~ /^[f|d|c|bc|bs]/) {
          my %ship=("f","Frigate","d","Destroyer","c","Cruiser","bc","Battle Cruiser","bs","Battleship");
          $_[ARG2]="open 1 Tech 1 $ship{$shiptype} giveaway of winner's choice, sponsored by $contact";
          $kernel->delay_set(irc_botcmd_give => 1, $_[ARG0],$_[ARG1],$_[ARG2] );
          $kernel->delay_set(say => 120, $_[ARG1],"/me - One minute left until the giveaway for a Tech 1 $ship{$shiptype} of the winner's choice is closed. Get your !enter cmds in now!");
          $kernel->delay_set(say => 170, $_[ARG1],"/me - Ten seconds left until the giveaway for a Tech 1 $ship{$shiptype} of the winner's choice is closed. Get your !enter cmds in now!");
          $_[ARG2]="close";
          $kernel->delay_set(irc_botcmd_give => 180, $_[ARG0],$_[ARG1],$_[ARG2] );
          $_[ARG2]="draw";
          $kernel->delay_set(irc_botcmd_give => 190, $_[ARG0],$_[ARG1],$_[ARG2] );
          $kernel->delay_set(say => 195, $_[ARG1],"/me - Please contact $contact for your prize.");
     } else {
          $irc->yield(privmsg => $where, "/me - Cmd must contain f,d,c,bc,bs for ship type.");
     }
     return;
}

sub irc_botcmd_top10 {
     my $nick = (split /!/, $_[ARG0])[0];
     my $where = $_[ARG1];
     if (!$irc->is_channel_operator($where,$nick)) {
          return;
     }
     my $sth = $dbh->prepare('SELECT TwitchID,Tokens FROM followers ORDER BY Tokens DESC LIMIT 10');
     $sth->execute();
     $irc->yield(privmsg => $where, "/me - The top 10 token holders are:");
     my $rank = 0;
     while (my @row = $sth->fetchrow_array) {
          $rank = $rank + 1;
          $irc->yield(privmsg => $where, "/me - $rank: $row[0], with $row[1] tokens.");
     }
     $sth->finish;
}

sub irc_botcmd_botstats {
     my $nick = (split /!/, $_[ARG0])[0];
     my $where = $_[ARG1];
     if (!$irc->is_channel_operator($where,$nick)) {
          return;
     }
     my $sth = $dbh->prepare('SELECT COUNT(*) FROM followers');
     $sth->execute();
     my ($total_users) = $sth->fetchrow_array;
     $sth->finish;
     $sth = $dbh->prepare('SELECT COUNT(*) FROM rushlock_online_viewers');
     $sth->execute();
     my ($total_online) = $sth->fetchrow_array;
     $sth->finish;
     $irc->yield(privmsg => $where, "/me - Total usernames in DB: $total_users, Current users in chat: $total_online.");
}

sub irc_botcmd_multitw {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     if (!$irc->is_channel_operator($where,$nick)) {
          return;
     }
     my @watch = split(' ',$arg);
     my %seen;
     for ( my $i = 0; $i <= $#watch ; ) {
          splice @watch, --$i, 1 if $seen{$watch[$i++]}++;
     }
     my $num_channels = scalar(@watch);
     if ($num_channels < 2) {
          $irc->yield(privmsg => $where, "/me - Must use more than one channel name.");
          return;
     }
     my $content = "/me - http://multitwitch.tv";
     foreach (@watch) {
          $content .= "/$_";
     }
     $irc->yield(privmsg => $where, $content);
     return;
}

sub say {
     my ($where, $msg) = @_[ARG0, ARG1];
     $msg = "/me - ".$msg;
     $irc->yield(privmsg => $where, $msg);
     return;
}

sub irc_botcmd_reload {
     my $nick = (split /!/, $_[ARG0])[0];
     my $where = $_[ARG1];
     if (!$irc->is_channel_operator($where,$nick)) {
          return;
     }
     my $sth = $dbh->prepare('SELECT * FROM epi_configuration');
     $sth->execute;
     my $ref = $sth->fetchall_hashref('setting');
     $debug = $ref->{'debug'}->{'value'};
     $interval = $ref->{'interval'}->{'value'};
     $log_token = $ref->{'log_token'}->{'value'};
     $token_exclude = $ref->{'token_exclude'}->{'value'};
     $consumer_key = $ref->{'tw_consumer_key'}->{'value'};
     $consumer_secret = $ref->{'tw_consumer_secret'}->{'value'};
     $tw_token = $ref->{'tw_token'}->{'value'};
     $tw_token_secret = $ref->{'tw_token_secret'}->{'value'};
     $log_chat = $ref->{'log_chat'}->{'value'};
     $token_give = $ref->{'token_give'}->{'value'};
     $sth->finish;
     $irc->yield(privmsg => $where, "/me - Values Updated.");
     return;
}

sub irc_botcmd_enter {
     my $nick = (split /!/, $_[ARG0])[0];
     my $where = $_[ARG1];
     if ($giveaway_open == 1) {
          my $sth = $dbh->prepare('SELECT * FROM followers WHERE TwitchID LIKE ?');
          $sth->execute($nick);
          my $ref = $sth->fetchrow_hashref();
          if ($ref) {
               if ($ref->{'Tokens'} >= $giveaway_threshold) {
                    my $sth2 = $dbh->prepare('INSERT IGNORE INTO entrylist SET TwitchID=?');
                    $sth2->execute($nick);
               } else {
                    my $logtime = Time::Piece->new->strftime('%m/%d/%Y %H:%M:%S');
                    print $clog "$logtime: $nick does not have enough tokens to enter $giveaway_title.\n" if $debug == 1;
               }
          }
     } else {
          $irc->yield(privmsg => $where, "/me - No contest is open, Taking 1 token from $nick!");
     }
     $sth->finish;
     return;
}
 
sub irc_botcmd_setnews {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     $arg =~ s/\s+$//;
     my $dt = DateTime->now;
     $arg = $dt->strftime("%b %d, %Y").": ".$arg;
     if ($irc->is_channel_operator($where,$nick)) {
          $arg =~ s/^\!\w//;
          my $sth = $dbh->prepare('UPDATE epi_info_cmds SET DisplayInfo=? WHERE CmdName LIKE ?');
          $sth->execute($arg,'news');
          $irc->yield(privmsg => $where, "/me - News Set!");
     }  
     return;
}

sub irc_botcmd_yield {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     if (!$arg) {
          return -1;
     }
     $arg =~ s/\s+$//;
     my @mins=("Tritanium","Pyerite","Mexallon","Isogen","Nocxium","Zydrine","Megacyte","Morphite");
     my $sth = $dbh->prepare('SELECT * FROM refineInfo WHERE refineItem LIKE ?');
     $sth->execute($arg);
     my $ref = $sth->fetchrow_hashref();
     if (!$ref) {
        $irc->yield(privmsg => $where, "/me - $arg is not a valid Item.");
        return -1;
     }
     my %items = %$ref;
     my $msg = "/me - $arg yields: ";
     foreach my $mineral (@mins) {
          my $amt = $ref->{$mineral};
          if ($amt > 0) {
               $msg = $msg.$mineral.":".$amt." ";
          }
     }
     $msg = $msg."for every ".$ref->{'batchsize'}." units refined.";
     $sth->finish;
     $irc->yield(privmsg => $where, $msg);
     return;
}
 
sub irc_botcmd_ice {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     $arg =~ s/\s+$//;
     my @mins=("Heavy Water","Helium Isotopes","Hydrogen Isotopes","Nitrogen Isotopes","Oxygen Isotopes","Liquid Ozone","Strontium Calthrates");
     my $sth = $dbh->prepare('SELECT * FROM icerefine WHERE icetype LIKE ?');
     $sth->execute($arg);
     my $ref = $sth->fetchrow_hashref();
     if (!$ref) {
        $irc->yield(privmsg => $where, "/me - $arg is not a valid Ice Type.");
        return -1;
     }
     my %items = %$ref;
     my $msg = "/me - $arg yields: ";
     foreach my $mineral (@mins) {
          my $amt = $ref->{$mineral};
          if ($amt > 0) {
               $msg = $msg.$mineral.":".$amt." ";
          }
     }
     $msg = $msg."for every ".$ref->{'RefineSize'}." unit refined.";
     $sth->finish;
     $irc->yield(privmsg => $where, $msg);
     return;
}

sub irc_botcmd_plex {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     $arg =~ s/\s+$//;
     &onlinecheck($nick);
     if (not defined $arg) {
          $irc->yield(privmsg => $where, "/me - Query must have in a SystemName or the word Hub. (e.g. !plex Hub)");
          return;
     }
     if ($arg eq "?") {
          $irc->yield(privmsg => $where, "/me - PLEX is an in-game item, that can be purchased with real money or in-game currency called ISK. PLEX gives you an extra 30 days of game time on your Eve Online account.");
          return;
     }
     $arg = lc($arg);
     if ($arg eq "hub") {
          my %hubs = ("Jita",30000142,"Hek",30002053,"Rens",30002510,"Amarr",30002187,"Dodixie",30002659);
          my $price="";
          while ((my $sysname, my $sysid) = each (%hubs)) {
               $price = $price.$sysname.":".currency_format('USD', &GetXMLValue($sysid,29668,"//sell/min"), FMT_COMMON)." ";
          }
          $irc->yield(privmsg => $where, "/me - Market Hub Prices for PLEX - $price");
     } else {
     my $sysid = &SystemLookup($arg,$where);
     if ($sysid == -1) {
          return;
     };
          my $maxprice = &GetXMLValue($sysid,29668,"//sell/min");
          if ($maxprice != 0) {
               $maxprice = currency_format('USD', $maxprice, FMT_COMMON);
               $irc->yield(privmsg => $where, "/me - PLEX is selling for $maxprice in $arg.");
          } else {
               $irc->yield(privmsg => $where, "/me - There is no PLEX for sell in $arg.");
          }
     }
     return;
}

sub irc_botcmd_pc {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     my ($sysname, $itemname) = split(' ', $arg, 2);
     if (not defined $itemname) {
          $irc->yield(privmsg => $where, "/me - Query must be in the form of SystemName and ItemName. (e.g. !pc Rens Punisher)");
          return;
     }
     $itemname =~ s/\s+$//;
     my $sysid = &SystemLookup($sysname,$where);
     if ($sysid == -1) { return; };
     my $itemid = &ItemLookup($itemname,$where);
     if ($itemid == -1) { return; };
     my $maxprice = &GetXMLValue($sysid,$itemid,"//sell/min");
     if ($maxprice != 0) {
          $maxprice = currency_format('USD', $maxprice, FMT_COMMON);
          $irc->yield(privmsg => $where, "/me - $itemname is selling for $maxprice in $sysname.");
     } else {
          $irc->yield(privmsg => $where, "/me - There is no $itemname for sell in $sysname.");
     }
     return;
}
 
sub irc_botcmd_rpc {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     my ($regname, $itemname) = split(',', $arg, 2);
     $itemname =~ s/\s+$//;
     if (not defined $itemname) {
          $irc->yield(privmsg => $where, "/me - Query must be in the form of RegionName,ItemName. (e.g. !rpc Lonetrek,Punisher)");
          return;
     }
     my $regid = &RegionLookup($regname,$where);
     if ($regid == -1) { return; };
     my $itemid = &ItemLookup($itemname,$where);
     if ($itemid == -1) { return; };
     my $maxprice = &GetXMLValueReg($regid,$itemid,"//sell/min");
     if ($maxprice != 0) {
          $maxprice = currency_format('USD', $maxprice, FMT_COMMON);
          $irc->yield(privmsg => $where, "/me - $itemname is selling for $maxprice in $regname region.");
     } else {
          $irc->yield(privmsg => $where, "/me - There is no $itemname for sell in $regname region.");
     }
     return;
}
 
sub irc_botcmd_pca {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     $arg =~ s/\s+$//;
     my ($sysname, $itemname) = split(' ', $arg, 2);
     if (not defined $itemname) {
          $irc->yield(privmsg => $where, "/me - Query must be in the form of SystemName and ItemName. (e.g. !pca Rens Punisher)");
          return;
     }
     my $sysid = &SystemLookup($sysname,$where);
     if ($sysid == -1) { return; };
     my $itemid = &ItemLookup($itemname,$where);
     if ($itemid == -1) { return; };
     my $avgprice = &GetXMLValue($sysid,$itemid,"//all/avg");
     my $volume = &GetXMLValue($sysid,$itemid,"//all/volume");
     if ($avgprice != 0) {
          $avgprice = currency_format('USD', $avgprice, FMT_COMMON);
          $irc->yield(privmsg => $where, "/me - $itemname has sold $volume units in the past 24 hours, at an average price of $avgprice in $sysname.");
     } else {
          $irc->yield(privmsg => $where, "/me - There is no $itemname for sell in $sysname.");
     }
     return;
}
 
sub irc_botcmd_hpc {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     $arg =~ s/\s+$//;
     &onlinecheck($nick);
     my %hubs = ("Jita",30000142,"Hek",30002053,"Rens",30002510,"Amarr",30002187,"Dodixie",30002659);
     my $itemid = &ItemLookup($arg,$where);
     if ($itemid == -1) { return; };
     my $price="";
     while ((my $sysname, my $sysid) = each (%hubs)) {
          my $hprice = &GetXMLValue($sysid,$itemid,"//sell/min");
          if ( $hprice > 0) {
               $price = $price.$sysname.":".currency_format('USD', $hprice, FMT_COMMON)." ";
          }
     }
     if ($price ne "") {
          $irc->yield(privmsg => $where, "/me - Market Hub Prices for $arg - $price");
     } else {
          $irc->yield(privmsg => $where, "/me - $arg is not available at any market hub.");
     }
}
 
sub irc_botcmd_server {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     my $url = get('https://api.eveonline.com/server/ServerStatus.xml.aspx');
     my $parser = new XML::LibXML;
     my $doc = $parser->parse_string($url);
     my $xpath="//result/onlinePlayers/text()";
     my $value = $doc->findnodes($xpath);
     $xpath="//currentTime/text()";
     my $time = $doc->findvalue($xpath);
     $xpath="//result/serverOpen/text()";
     my $online = $doc->findnodes($xpath);
     if ($online =~ /True/) {
          $irc->yield(privmsg => $where, "/me - Server is Online with $value Players. Server Time: $time");
     } else {
          $irc->yield(privmsg => $where, "/me - Server is currently Offline. Server Time: $time");
     }
     return;
}

sub irc_botcmd_zkb {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $charname) = @_[ARG1, ARG2];
     if (not defined $charname) {
          $irc->yield(privmsg => $where, "/me - Query must be in the form of a single character name. (e.g. !zkb Ira Warwick)");
          return;
     }
     my $charid = &CharIDLookup($charname);
     if ($charid == -1) {
          $irc->yield(privmsg => $where, "/me - There is no $charname in the Eve Universe.");
          return;
     };
     &ZkbLookup($charname,$charid,$where);
     return;
}

sub irc_botcmd_cinfo {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $corpname) = @_[ARG1, ARG2];
     if (not defined $corpname) {
          $irc->yield(privmsg => $where, "/me - Query must be in the form of a single corporation name. (e.g. !cinfo The Romantics)");
          return;
     }
     my $corpid = &CharIDLookup($corpname);
     if ($corpid == -1) {
          $irc->yield(privmsg => $where, "/me - There is not a corporation named $corpname in the Eve Universe.");
          return;
     };
     &CorpLookup($corpname,$corpid,$where);
     return;
}

sub CorpLookup {
     my $url = "https://api.eveonline.com/corp/CorporationSheet.xml.aspx?corporationID=$_[1]";
     my $content = get($url);
     if (not defined $content) {
          $irc->yield(privmsg => $_[2], "/me - $_[0] was not found.");
          return;
     }    
     my $parser = new XML::LibXML;
     my $doc = $parser->parse_string($content);
     my $xpath="//ceoName";
     my $ceoname = $doc->findvalue($xpath);
     $xpath="//memberCount";
     my $memcount = $doc->findvalue($xpath);
     $xpath="//stationName";
     my $station = $doc->findvalue($xpath);
     $irc->yield(privmsg => $_[2], "/me - $_[0] - CEO: $ceoname - Members: $memcount - HQ: $station");
     return;
}

sub GetXMLValue {
     my $url = "http://api.eve-central.com/api/marketstat?usesystem=$_[0]&typeid=$_[1]";
     my $parser = new XML::LibXML;
     my $doc = $parser->parse_file("$url");
     my $xpath="//sell/min";
     my $value = $doc->findvalue($_[2]);
     return $value;
}
 
sub GetXMLValueReg {
     my $url = "http://api.eve-central.com/api/marketstat?regionlimit=$_[0]&typeid=$_[1]";
     my $parser = new XML::LibXML;
     my $doc = $parser->parse_file("$url");
     my $xpath="//sell/min";
     my $value = $doc->findvalue($_[2]);
     return $value;
}
 
sub ItemLookup {
     my $sth = $dbh->prepare('SELECT typeID as ItemID FROM invTypes WHERE typeName LIKE ?');
     $sth->execute($_[0]);
     my $ref = $sth->fetchrow_hashref();
     if (!$ref) {
        $irc->yield(privmsg => $_[1], "/me - $_[0] is not a valid Item.");
        return -1;
     }
     my $itemid = $ref->{'ItemID'};
     $sth->finish;
     return $itemid;
}
 
sub SystemLookup {
     my $sth = $dbh->prepare('SELECT SystemID FROM systemids WHERE SystemName LIKE ?');
     $sth->execute($_[0]);
     my $ref = $sth->fetchrow_hashref();
     if (!$ref) {
        $irc->yield(privmsg => $_[1], "/me - $_[0] is not a valid System.");
        return -1;
     }
     my $sysid = $ref->{'SystemID'};
     $sth->finish;
     return $sysid;
}
 
sub RegionLookup {
     my $sth = $dbh->prepare('SELECT RegionID FROM regionids WHERE RegionName LIKE ?');
     $sth->execute($_[0]);
     my $ref = $sth->fetchrow_hashref();
     if (!$ref) {
        $irc->yield(privmsg => $_[1], "/me - $_[0] is not a valid Region.");
        return -1;
     }
     my $regid = $ref->{'RegionID'};
     $sth->finish;
     return $regid;
}

sub CharIDLookup {
     my $url = "https://api.eveonline.com/eve/CharacterID.xml.aspx?names=$_[0]";
     my $content = get($url);
     my $parser = new XML::LibXML;
     my $doc = $parser->parse_string($content);
     my $xpath="//result/rowset/row/\@characterID";
     my $value = $doc->findvalue($xpath);
     if ($value == 0) {
          return -1;
     } else {
          return $value;
     }
}

# ZkbLookup: Args: 0 - Character Name, 1 - Character ID, 2 - IRC Channel to send the msg to.
sub ZkbLookup {
     my $return = &CheckzkbCache($_[1],$_[0],$_[2]);
     if ($return == 1) {
          print $clog "Found record in killcache for $_[0]\n";
          return;
     } else {
          print "zkillboard lookup: From channel: $_[2] For Character: $_[0] CharID: $_[1]\n" if $debug == 1;
          my $url = "https://zkillboard.com/api/stats/characterID/$_[1]/xml/";
          my $browser = LWP::UserAgent->new;
          my $can_accept = HTTP::Message::decodable;
          $browser->agent('Evepriceinfo/Chatbot');
          $browser->from('rjreed67@gmail.com');
          my $content = $browser->get($url,'Accept-Encoding' => $can_accept,);
          print $content if $debug == 1;
          if ($content->decoded_content =~ m/html/i) {
               $irc->yield(privmsg => $_[2], "$_[0] was not found at zKillboard.com.");
               return;
          }
          print $content->headers()->as_string if $debug == 1;
          my $parser = new XML::LibXML;
          my $doc = $parser->parse_string($content->decoded_content);
          my $xpath="//row[\@type='count']/\@destroyed";
          my $shipdest = $doc->findvalue($xpath);
          $xpath="//row[\@type='count']/\@lost";
          my $shiplost = $doc->findvalue($xpath);
          $xpath="//row[\@type='isk']/\@destroyed";
          my $iskdest = $doc->findvalue($xpath);
          $xpath="//row[\@type='isk']/\@lost";
          my $isklost = $doc->findvalue($xpath);
          my $eff = sprintf("%.1f",($shipdest/($shipdest+$shiplost))*100);
          my $iskeff = sprintf("%.1f",($iskdest/($iskdest+$isklost))*100);
          my $msg = "/me - $_[0] has ";
          if ($shipdest == 0) {
               $msg = $msg."not destroyed any ships, ";
          } elsif ($shipdest == 1) {
               $msg = $msg."destroyed $shipdest ship, worth ".currency_format('USD', $iskdest, FMT_COMMON)." ";
          } else {
               $msg = $msg."destroyed $shipdest ships, worth ".currency_format('USD', $iskdest, FMT_COMMON)." ";
          }
          $msg = $msg."and ";
          if ($shiplost == 0) {
               $msg = $msg."has not lost any ships.";
          } elsif ($shiplost == 1) {
               $msg = $msg."lost $shiplost ship, worth ".currency_format('USD', $iskdest, FMT_COMMON).".";
          } else {
               $msg = $msg."lost $shiplost ships, worth ".currency_format('USD', $isklost, FMT_COMMON).".";
          }
          $msg .= " Ship Efficiency: $eff% ISK Efficiency: $iskeff%";
          $irc->yield(privmsg => $_[2],$msg);
          my $dt = DateTime::Format::DateParse->parse_datetime($content->header('Expires'));
          my $sth = $dbh->prepare('INSERT INTO killcache SET CharID=?,CharName=?,DestShips=?,DestISK=?,LostShips=?,LostISK=?,DataExpire=?');
          print "Inserting: $_[1]:$_[0]:$shipdest:$iskdest:$shiplost:$isklost:$dt\n" if $debug == 1;
          $sth->execute($_[1],$_[0],$shipdest,$iskdest,$shiplost,$isklost,$dt);
          return;
     }
}

# CheckzkbCache - $Args 0 - CharacterID, 1 - Character Name, 2 - Channel to send msg to. - Returns a value of 1 if valid cache entry is found
sub CheckzkbCache {
     print "Called with: $_[0]:$_[1]:$_[2]\n" if $debug == 1;
     my $sth = $dbh->prepare('SELECT * FROM killcache WHERE CharID LIKE ?');
     $sth->execute($_[0]);
     my $ref = $sth->fetchrow_hashref();
     if (!$ref) {
          return false;
     } else {
          my $dt1 = DateTime->now(time_zone => "GMT");
          my $dt2 = DateTime::Format::MySQL->parse_datetime($ref->{'DataExpire'});
          my $cmp = DateTime->compare($dt1,$dt2);
          if ($cmp > 0) {
               $sth->finish;
               $sth = $dbh->prepare('DELETE FROM killcache WHERE CharID=?');
               $sth->execute($_[0]);
               $sth->finish;
               return false;
          } else {
               my $shipdest = $ref->{'DestShips'};
               my $iskdest = $ref->{'DestISK'};
               my $shiplost = $ref->{'LostShips'};
               my $isklost = $ref->{'LostISK'};
               my $eff = sprintf("%.1f",($shipdest/($shipdest+$shiplost))*100);
               my $iskeff = sprintf("%.1f",($iskdest/($iskdest+$isklost))*100);
               my $msg = "/me - $_[1] has ";
               if ($shipdest == 0) {
                    $msg = $msg."not destroyed any ships, ";
               } elsif ($shipdest == 1) {
                    $msg = $msg."destroyed $shipdest ship, worth ".currency_format('USD', $iskdest, FMT_COMMON)." ";
               } else {
                    $msg = $msg."destroyed $shipdest ships, worth ".currency_format('USD', $iskdest, FMT_COMMON)." ";
               }
               $msg = $msg."and ";
               if ($shiplost == 0) {
                    $msg = $msg."has not lost any ships.";
               } elsif ($shiplost == 1) {
                    $msg = $msg."lost $shiplost ship, worth ".currency_format('USD', $iskdest, FMT_COMMON).".";
               } else {
                    $msg = $msg."lost $shiplost ships, worth ".currency_format('USD', $isklost, FMT_COMMON).".";
               }
               $msg .= " Ship Efficiency: $eff% ISK Efficiency: $iskeff%";
               $irc->yield(privmsg => $_[2],$msg);
               return true;
          }
     }
}

sub tw_stream_online {
     my $ua = LWP::UserAgent->new;
     my $live = $ua->get($tw_following,"Accept"=>"application/vnd.twitchtv.v2+json","Authorization"=>"$tw_pwd");
     my $code = $live->code();
     if ($code =~ /^5/) { return 0; }
     my $decode = decode_json( $live->content );
     my @streams = @{$decode->{'streams'}};
     my $id = $streams[0]->{'_id'};
     return 1 if $id;
     return 0;
}

sub tw_user_follow {
     my $url = $tw_follow;
     $url =~ s/USER/$_[0]/g;
     my $ua = LWP::UserAgent->new;
     my $live = $ua->get($url,"Accept"=>"application/vnd.twitchtv.v2+json","Authorization"=>"$tw_pwd");
     my $code = $live->code();
     if ($code =~ /^5/) { return 0; }
     print $live->status_line."\n" if $debug==1;
     if ( $live->status_line =~ "404" ) {
        return 1;
     } else {
        return 0;
     }
}

sub tw_is_subscriber {
     my $logtime = Time::Piece->new->strftime('%m/%d/%Y %H:%M:%S');
     print $clog "$logtime: Checking $_[0] to see if they are a subscriber.\n" if $debug==1;
     my $sth = $dbh->prepare('SELECT TwitchName FROM Rushlock_TwitchSubs WHERE TwitchName LIKE ?');
     $sth->execute($_[0]);
     my @ref = $sth->fetchrow_array();
     if ($sth->rows == 0) {
          print $clog "$logtime: $_[0] is not a subscriber.\n" if $debug==1;
          return 0;
     } else {
          print $clog "$logtime: $_[0] is a subscriber.\n" if $debug==1;
          return 1;
     }
}

sub onlinecheck {
     my $sth = $dbh->prepare('INSERT IGNORE INTO rushlock_online_viewers SET TwitchID = ?');
     $sth->execute($_[0]);
     $sth->finish;
     return;
}
