#!/bin/perl

use strict;
use warnings;
use Config::Simple;
use POE;
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::BotCommand;
use POE::Component::IRC::Plugin::Connector;
use DBI;
use Log::Log4perl;
use LWP::UserAgent;
use Time::HiRes qw(time);
use Time::Piece;
use Data::Dumper;
use lib "/opt/evepriceinfo";
use Token qw(token_add token_take);
use EPIUser qw(is_subscriber is_authorized is_owner);

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
my $debug = $ref->{'debug'}->{'value'};
my $tw_following = $ref->{'tw_following'}->{'value'};
my $tw_follow = $ref->{'tw_follow'}->{'value'};
my $tw_pwd = $ref->{'tw_pwd'}->{'value'};;
my $interval = $ref->{'interval'}->{'value'};
my $install_dir = $ref->{'install_dir'}->{'value'};
my $log_dir = $install_dir.$ref->{'log_dir'}->{'value'};
my @channels = ($ref->{'channel'}->{'value'});
my $auto_grant = $ref->{'auto_grant'}->{'value'};
my $token_give = $ref->{'token_give'}->{'value'};
my $log_conf = $install_dir.$ref->{'log_conf'}->{'value'};
$sth->finish;

Log::Log4perl::init_and_watch($log_conf,60);
my $logger = Log::Log4perl->get_logger;
my $tokenlogger = Log::Log4perl->get_logger("token");

my $offline_timer = 0;
my $chatlines = 0;
my $online_timer = 0;
my $grant_id;

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

my @cmds = ();
my %help = ();

push(@cmds,'_start');
push(@cmds,'say');
push(@cmds,'giveaway_add');
push(@cmds,'tick');
$sth = $dbh->prepare('SELECT * FROM epi_commands WHERE CmdModule like ?');
$sth->execute('giveaway');
$ref = $sth->fetchall_hashref('CmdKey');
foreach ( keys %$ref ) {
     push(@cmds,"irc_botcmd_".$ref->{$_}->{'Command'});
     $help{$ref->{$_}->{'Command'}}=$ref->{$_}->{'HelpInfo'};
}
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
                main => [ @cmds ],
        ],
);

$poe_kernel->run();
 
sub _start {
     $logger->debug("epi_giveaway.pl has started!");
     my ($kernel, $heap) = @_[KERNEL ,HEAP];
     $heap->{connector} = POE::Component::IRC::Plugin::Connector->new();
     $irc->plugin_add('Connector' => $heap->{connector} );
     $heap->{next_alarm_time} = int(time()) + $interval;
     $kernel->alarm(tick => $heap->{next_alarm_time});
     $irc->plugin_add('BotCommand', POE::Component::IRC::Plugin::BotCommand->new(
        Addressed => 0,
        Prefix => '!',
        Method => 'privmsg',
        Ignore_unknown => 1,
        Commands => { %help },
        Help_sub => \&help,
     ));
     $irc->yield(register => qw(all));
     $irc->yield(connect => { } );
     return;
}

sub tick {
     my ($kernel,$heap) = @_[KERNEL,HEAP];
     $heap->{next_alarm_time}=int(time())+$interval;
     $kernel->alarm(tick => $heap->{next_alarm_time});
     if (&tw_stream_online("#rushlock")) {
          $logger->debug("Giveaway Online Tick: $online_timer");
          &auto_grant if $auto_grant;
     } else {
          if ($grant_id) {
               $online_timer = 0;
               $kernel->alarm_remove( $grant_id ) if $auto_grant;
               $grant_id = undef;
          }
          $logger->debug("Giveaway Offline Tick");
     }
     return;
}

sub irc_botcmd_wg500 {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     $arg =~ s/\s+$//;
     if (is_authorized($where,$nick)) {
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

sub irc_botcmd_give {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     if (!is_authorized($where,$nick)) {
          return;
     }
     $arg =~ s/\s+$//;
     $logger->info("Give function called by: $nick, with Args: $arg");
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
          $logger->info("Time Giveaway function called by: $nick with Args: $arg");
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
               my $sth = $dbh->prepare('UPDATE giveaway SET Winner=? WHERE GiveKey=?');
               if ($count > 0) {
                    $irc->yield(privmsg => $where, "/me - There are $count entries in the $giveaway_title.");
                    my $winner = $ref[int(rand(0+$count))];
                    $sth->execute($winner,$giveaway_key);
                    my $winner2 = "";
                    if ( &tw_user_follow($winner) == 0 ) {
                        $winner2 = $winner." (follower)";
                    } else {
                        $winner2 = $winner." (not following)";
                    }
                    $irc->yield(privmsg => $where, "/me - The winner of $giveaway_title is $winner2! Congratulations!");
                    $irc->yield(privmsg => $where, "/me - $winner! Come On Down!");
               } else {
                    $irc->yield(privmsg => $where, "/me - No one entered for $giveaway_title.");
                    $sth->execute("NoOne",$giveaway_key);
               }
               $sth->finish;
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
     if (!is_authorized($where,$nick)) {
          return;
     }
     if ($giveaway_open == true) {
          $irc->yield(privmsg => $where, "/me - A giveaway is still open. Please close the giveaway before attempting to do a new one.");
          return;
     }
     $logger->info("Timed Giveaway function called by: $nick");
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
     $_[ARG2]="$token_give";
     $kernel->delay_set(giveaway_add => 200, $_[ARG1], $_[ARG2] );
     return;
}

sub giveaway_add {
     my ($where, $change) = @_[ARG0, ARG1];
     my $sth = $dbh->prepare('SELECT Winner, GiveKey FROM giveaway WHERE AutoGive = 1 ORDER BY GiveKey LIMIT 1');
     $sth->execute;
     my ($user, $giveaway_key) = $sth->fetchrow_array;
     $sth->finish;
     $sth = $dbh->prepare('UPDATE giveaway SET AutoGive=0 WHERE GiveKey=?');
     $sth->execute($giveaway_key);
     $sth->finish;
     $sth = $dbh->prepare('SELECT * FROM followers WHERE TwitchID LIKE ?');
     $sth->execute($user);
     my $ref = $sth->fetchrow_hashref();
     if (!$ref) {
          $irc->yield(privmsg => $where, "/me - User $user not found in token table.");
     } else {
          token_add("evepriceinfo",$change,$user);
          $irc->yield(privmsg => $where, "/me - $change tokens added to $user balance.");
          $giveaway_autogive = 0;
     }
     $sth->finish;
     return;
}

sub irc_botcmd_t1sgw {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     $arg =~ s/\s+$//;
     if (!is_authorized($where,$nick)) {
          return;
     }
     $logger->info("Tech 1 ship Giveaway called by $nick with Args: $arg");
     my ($kernel, $self) = @_[KERNEL, OBJECT];
     my ($shiptype, $contact) = split(/ /,$arg);
     if ($contact eq '') {
          $contact = "Rushlock";
     }
     if ($shiptype =~ /^[f|d|c|bc|bs]/) {
          my %ship=("f","Frigate","d","Destroyer","c","Cruiser","bc","Battle Cruiser","bs","Battleship");
          $_[ARG2]="open 1 Tech 1 $ship{$shiptype} giveaway of winner's choice, sponsored by $contact";
          $kernel->delay_set(irc_botcmd_give => 1, $_[ARG0],$_[ARG1],$_[ARG2] );
          $kernel->delay_set(say => 120, $_[ARG1],"One minute left until the giveaway for a Tech 1 $ship{$shiptype} of the winner's choice is closed. Get your !enter cmds in now!");
          $kernel->delay_set(say => 170, $_[ARG1],"Ten seconds left until the giveaway for a Tech 1 $ship{$shiptype} of the winner's choice is closed. Get your !enter cmds in now!");
          $_[ARG2]="close";
          $kernel->delay_set(irc_botcmd_give => 180, $_[ARG0],$_[ARG1],$_[ARG2] );
          $_[ARG2]="draw";
          $kernel->delay_set(irc_botcmd_give => 190, $_[ARG0],$_[ARG1],$_[ARG2] );
          $kernel->delay_set(say => 195, $_[ARG1],"Please contact $contact for your prize.");
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
                    $logger->debug("$nick does not have enough tokens to enter $giveaway_title.");
               }
          }
     } else {
          $irc->yield(privmsg => $where, "/me - No contest is open, Taking 1 token from $nick!");
     }
     $sth->finish;
     return;
}
 
sub auto_grant {
     my ($kernel, $self) = @_[KERNEL, OBJECT];
     $logger->debug("Auto Grant Called: $online_timer.");
     if ($online_timer < 1) {
          $grant_id = $kernel->delay_set(irc_botcmd_tgw => 1800, 'evepriceinfo!evepriceinfo@evepriceinfo.twitch.tv','#rushlock','');
          $logger->debug("Auto Grant Error: $!");
          $online_timer = $online_timer + 1;
     } else {
          $online_timer = 0;
     }
}

sub say {
     my ($where, $msg, $cmd) = @_[ARG0, ARG1, ARG2];
     $msg = "/me - ".$msg if !$cmd;
     $irc->yield(privmsg => $where, $msg);
     return;
}

sub tw_stream_online {
     my $channelname = $_[0];
     $channelname =~ s/^#//g;
     my $sth = $dbh->prepare('SELECT * from channel_status WHERE Channel like ?');
     $sth->execute($channelname);
     my @ref = $sth->fetchrow_array();
     return true if ($ref[2] =~ m/Online/);
     return false;
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
