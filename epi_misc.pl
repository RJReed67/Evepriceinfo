#!/bin/perl

use strict;
use warnings;
use Config::Simple;
use Data::Dumper;
use DateTime;
use DateTime::Duration;
use DateTime::Format::MySQL;
use DateTime::Format::DateParse;
use DBI;
use Log::Log4perl;
use POE;
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::BotCommand;
use POE::Component::IRC::Plugin::Connector;
use Switch;
use lib "/opt/evepriceinfo";
use Token qw(token_add token_take);
use EPIUser qw(is_owner is_subscriber);

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
my $tw_pwd = $ref->{'tw_pwd'}->{'value'};;
my $install_dir = $ref->{'install_dir'}->{'value'};
my @channels = ($ref->{'channel'}->{'value'});
my $log_conf = $install_dir.$ref->{'log_conf'}->{'value'};
$sth->finish;

Log::Log4perl::init_and_watch($log_conf,60);
my $logger = Log::Log4perl->get_logger;
my $tokenlogger = Log::Log4perl->get_logger("token");

my @cmds = ();
my %help = ();

push(@cmds,'_start');
$sth = $dbh->prepare('SELECT * FROM epi_commands WHERE CmdModule like ?');
$sth->execute("misc");
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
        WhoJoiners => 0,
) or die "Error: $!";

POE::Session->create(
        package_states => [
                main => [ @cmds ],
        ],
);

$poe_kernel->run();
 
sub _start {
     $logger->info("epi_info_cmds.pl starting!");
     my ($kernel, $heap) = @_[KERNEL ,HEAP];
     $heap->{connector} = POE::Component::IRC::Plugin::Connector->new();
     $irc->plugin_add('Connector' => $heap->{connector} );
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

sub irc_botcmd_addtweetid {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $user) = @_[ARG1, ARG2];
     $user =~ s/\s+$// if $user;
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
               $logger->info("Twitch ID $nick has been linked to $user.");
          } else {
               $sth = $dbh->prepare('UPDATE TwitterID2TwitchID SET TwitterID = ? WHERE TwitchID = ?');
               $sth->execute($user,$nick) or die "Error: ".$sth->errstr;
               $irc->yield(privmsg => $where, "/me - $nick updated to $user.");
               $logger->info("Twitch ID $nick has been updated to $user.");
          }
     }
     return;
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

sub irc_botcmd_tip {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     my $tips = $dbh->selectrow_array('SELECT * FROM TipJar');
     $irc->yield(privmsg => $where, "/me - Current tokens in the jar: $tips") if !$arg;
     $irc->yield(privmsg => $where, "/me - Usage: !tip <#ofTokens>") if !$arg;
     return if !$arg;
     if ($arg !~ /^\d+$/) {
          $irc->yield(privmsg => $where, "/me - $nick, The number of tokens must be a number!");
          return;
     }
     if ($arg < 5) {
          $irc->yield(privmsg => $where, "/me - $nick, you have to tip me 5 or more tokens!");
          return;
     }
     my $max = $dbh->selectrow_array("SELECT Tokens FROM followers WHERE TwitchID = \"$nick\"");
     if ($arg > $max) {
          $irc->yield(privmsg => $where, "/me - $nick, you cannot tip me more tokens than you have!");
          return;
     }
     my $lasttip = $dbh->selectrow_array("SELECT TipTime FROM TipTime WHERE TipperID = \"$nick\"");
     my $duration;
     if ($lasttip) {
          my $dt1 = DateTime::Format::MySQL->parse_datetime($lasttip);
          my $dt2 = DateTime->now(time_zone=>'local');
          my $days = ($dt2 - $dt1)->days;
          my $hours = ($dt2 - $dt1)->hours;
          my $mins = ($dt2 - $dt1)->minutes;
          my $secs = ($dt2 - $dt1)->seconds;
          $duration = ($days * 86400) + ($hours * 3600) + ($mins * 60) + $secs;
     } else {
          $duration = 301;
     }
     if ($duration < 300) {
          $irc->yield(privmsg => $where, "/me - $nick, I love tips, but the boss says that you cannot tip me more than once every 5 minutes.");
          return;
     }
     my $sth = $dbh->prepare('INSERT INTO TipTime (TipperID,TipTime) VALUES (?,NULL) ON DUPLICATE KEY UPDATE TipTime = NULL');
     $sth->execute($nick);
     $sth->finish;
     my $result = token_take("evepriceinfo",$arg,$nick);
     if ($result) {
          $irc->yield(privmsg => $where, "$arg tokens put in the Tip Jar by $nick!");
     } else {
          $irc->yield(privmsg => $where, "Could not get tokens! Alert rjreed67!");
          return;
     }
     $tips = $tips + $arg;
     $sth = $dbh->prepare('UPDATE TipJar SET TotalTokens = ?');
     $sth->execute($tips) or die "Error: ".$sth->errstr;
     $sth->finish;
     $irc->yield(privmsg => $where, "/me - There are currently $tips tokens in my jar.");
     my $rand = rand(100)%100;
     my $winner = false;
     switch ($arg) {
          case [5..100]       {$winner = true if $rand < 1}
          case [101..200]     {$winner = true if $rand < 2}
          case [201..300]     {$winner = true if $rand < 3}
          case [301..400]     {$winner = true if $rand < 4}
          else                {$winner = true if $rand < 5}
     }
     if ($winner) {
          $irc->yield(privmsg => $where, "/me - You know what? I am going to split my tips with you!");
          my $give_amt = int($tips/2);
          my $result = token_add("evepriceinfo",$give_amt,$nick);
          if ($result) {
               $irc->yield(privmsg => $where, "$give_amt tokens given to $nick!");
          } else {
               $irc->yield(privmsg => $where, "Could not give tokens! Alert rjreed67!");
               return;
          }
          $sth = $dbh->prepare('Update TipJar SET TotalTokens = 0');
          $sth->execute or die "Error: ".$sth->errstr;
          $sth->finish;
     }
     return;
}

sub irc_botcmd_bacon {
     my $nick = (split /!/, $_[ARG0])[0];
     my $where = $_[ARG1];
     return if &tw_stream_online($where);
     my @msg = ('September 3rd is "International Bacon Day"',
                'Baconnaise is Vegetarian!',
                'Bacon is addictive; it contains six types of umami. Umami produces an addictive neurochemical response',
                'Each year in the US more than 1.7 billion lbs. of bacon are consumed in food service, which is equivalent to the weight of 8.5 Nimitz class aircraft carriers.',
                'Bacon cures hangovers',
                '69% of all food service operators serve bacon',
                'There is a bust of Kevin Bacon made of bacon',
                'The price of pork bellies is the highest it has been since 1988',
                'Bacon is one of the oldest processed meats in history. The Chinese began salting pork bellies as early as 1500 B.C.',
                'Canadian Bacon is not really bacon, it is fully-cooked smoked pork loin',
                'Pregnant women should eat bacon. Choline, which is found in bacon, helps fetal brain development',
                'Bacon and eggs are eatten together 71% of the time',
                'Bacon appeals to males slightly more than females',
                'Bacon is consumed at breakfast an average of 12 times per person per year',
                'A 250 lb pig yields about 23 lbs of bacon',
                'Bacon accounts for 19% of all pork eaten in the home',
                'Bacon consumption occurs 59% during weekdays and 41% on the weekends',
                'People over the age of 34 make up most bacon consumption',
                'Bacon accounted for nearly half of breakfast meat serving volume',
                'More than half of all homes (53%) keep bacon on hand at all times');
     $irc->yield(privmsg => $where, "/me - $msg[rand(@msg)%@msg]");
     return;
}

sub irc_botcmd_auth {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $user) = @_[ARG1, ARG2];
     if (!$user) {
          return;
     }
     if (is_owner($nick)) {
          my $sth = $dbh->prepare('INSERT IGNORE INTO AuthorizedUsers SET TwitchID = ?');
          $sth->execute($user);
          $irc->yield(privmsg => $where, "/me - $user is now an authorized user.");
          $logger->info("$nick added $user as an authorized user.");
          $sth->finish;
     }
     return;
}

sub irc_botcmd_deauth {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $user) = @_[ARG1, ARG2];
     if (!$user) {
          return;
     }
     if (is_owner($nick)) {
          my $sth = $dbh->('DELETE IGNORE FROM AuthorizedUsers WHERE TwitchID = ?');
          $sth->execute($user);
          $irc->yield(privmsg => $where, "/me - $user is no longer an authorized user.");
          $logger->info("$nick removed $user as an authorized user.");
          $sth->finish;
     }
     return;
}

sub irc_botcmd_tweet {
     my $nick = (split /!/, $_[ARG0])[0];
     my $where = $_[ARG1];
     my $tweet = $dbh->selectrow_array('SELECT Tweet FROM TwitterInfo');
     $irc->yield(privmsg => $where, "/me - Latest Tweet from Rushlock: $tweet");
     return;
}

sub irc_botcmd_que {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     my $sth;
     my $user;
     if (is_owner($nick)) {
          if ($arg =~ /clear/) {
               $sth = $dbh->prepare('TRUNCATE GameQueue');
               $sth->execute;
               $irc->yield(privmsg => $where, "/me - Player Queue Cleared.");
          }
          if ($arg =~ /pull/) {
               $user = $dbh->selectrow_array("SELECT TwitchID FROM GameQueue ORDER BY QueTime LIMIT 1");
               if (!$user) {
                    $irc->yield(privmsg => $where, "/me - No one wants to play!");
               } else {
                    $sth = $dbh->prepare('DELETE IGNORE FROM GameQueue WHERE TwitchID = ?');
                    $sth->execute($user);
                    $sth->finish;
                    $irc->yield(privmsg => $where, "/me - Next on the Queue is: $user, time to play!");
               }
          }
          if ($arg =~ /list/) {
               my $sth = $dbh->prepare('SELECT TwitchID FROM GameQueue ORDER BY QueTime ASC LIMIT 10');
               $sth->execute();
               $irc->yield(privmsg => $where, "/me - The Players in the queue, in order are: (Up to 10)");
               my $rank = 0;
               while (my @row = $sth->fetchrow_array) {
                    $rank = $rank + 1;
                    $irc->yield(privmsg => $where, "/me - $rank: $row[0]");
               }
               if ($rank == 0) {
                    $irc->yield(privmsg => $where, "/me - No one in the queue.");                    
               }
               $sth->finish;
          }
     }
     if (is_subscriber($nick)) {
          if (!$arg) {
               # Add Nick to queue, if it isn't there already.
               $user = $dbh->selectrow_array("SELECT TwitchID FROM GameQueue ORDER BY QueTime LIMIT 1");
               if ($user =~ /$nick/) {
                    $irc->yield(privmsg => $where, "/me - $user, your name is already in the queue.");
               } else {
                    $sth = $dbh->prepare('INSERT IGNORE INTO GameQueue SET TwitchID=?, QueTime=Null');
                    $sth->execute($nick);
                    $irc->yield(privmsg => $where, "/me - $nick has been added to Player Queue.");
               }
          }
     } else {
          $irc->yield(privmsg => $where, "/me - Must be a Sub/Patreon to add your name to the Player Queue.");
     }
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

sub help {
     return;
}
