#!/bin/perl

use strict;
use warnings;
use Config::Simple;
use DateTime;
use DateTime::Duration;
use DateTime::Format::MySQL;
use DateTime::Format::DateParse;
use POE;
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::BotCommand;
use POE::Component::IRC::Plugin::Connector;
use DBI;
use Log::Log4perl;
use Data::Dumper;
use lib "/opt/evepriceinfo";
use Token qw(token_add token_take);

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
my $install_dir = $ref->{'install_dir'}->{'value'};
my @channels = ($ref->{'channel'}->{'value'});
my $log_conf = $install_dir.$ref->{'log_conf'}->{'value'};
$sth->finish;

Log::Log4perl::init_and_watch($log_conf,60);
my $logger = Log::Log4perl->get_logger;
 
my @cmds = ();
my %help = ();

push(@cmds,'_start');
$sth = $dbh->prepare('SELECT * FROM epi_commands WHERE CmdModule like ?');
$sth->execute('game');
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

sub irc_botcmd_slot {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     return if &tw_stream_online($where);
     if (!$arg) {
          $irc->yield(privmsg => $where, "/me - TwitchSlots, use 1 to 3 tokens. Payout Table: http://tinyurl.com/twitchslots");
          return;
     }
     if ($arg =~ /help/) {
          $irc->yield(privmsg => $where, "/me - TwitchSlots, use 1 to 3 tokens. Payout Table: http://tinyurl.com/twitchslots");
          return;
     }
     if ($arg !~ /^\d+$/) {
          $irc->yield(privmsg => $where, "/me - $nick, The number of tokens must be a number!");
          return;
     }
     $irc->yield(privmsg => $where, "/me - Must specify how many tokens to use (1 - 3).") if !$arg;
     return if !$arg;
     if ($arg < 1 || $arg > 3) {
          $irc->yield(privmsg => $where, "/me - Must use 1 to 3 tokens for the slot machine.");
          return;
     }
     my $max = $dbh->selectrow_array("SELECT Tokens FROM followers WHERE TwitchID = \"$nick\"");
     if ($arg > $max) {
          $irc->yield(privmsg => $where, "/me - $nick, you do not have $arg tokens!");
          return;
     }
     my $lastslot = $dbh->selectrow_array("SELECT SlotTime FROM SlotTime WHERE TwitchID = \"$nick\"");
     my $duration;
     if ($lastslot) {
          my $dt1 = DateTime::Format::MySQL->parse_datetime($lastslot);
          my $dt2 = DateTime->now(time_zone=>'local');
          my $hours = ($dt2 - $dt1)->hours;
          my $mins = ($dt2 - $dt1)->minutes;
          my $secs = ($dt2 - $dt1)->seconds;
          $duration = ($hours * 3600) + ($mins * 60) + $secs;
     } else {
          $duration = 301;
     }
     if ($duration < 300) {
          $irc->yield(privmsg => $where, "/me - $nick, you can only play once every 5 minutes.");
          return;
     }
     my $sth = $dbh->prepare('INSERT INTO SlotTime (TwitchID,SlotTime) VALUES (?,NULL) ON DUPLICATE KEY UPDATE SlotTime = NULL');
     $sth->execute($nick);
     $sth->finish;
     token_take("evepriceinfo",$arg,$nick);
     my @wheel1 = ([';P',':)','R)',':(',';P',';)','<3',':(','B)',';)','R)',':P',':O','O_o','R)',':D',':O',':z','<3',':(','B)',';)'],
                   [1,4,6,7,9,16,20,21,25,28,30,31,33,39,41,42,44,52,56,57,61,64],
                   [3,5,6.8,15,19,20,24,27,29,30,32,38,40,41,43,51,55,56,60,63,64],
                   [2,0,4,0,2,0,5,0,3,0,4,0,1,0,4,0,1,0,5,0,3,0]);
     my @wheel2 = ([';P',':)','R)',':(',';P',';)','<3',':(','B)',';)','R)',':P',':O','O_o','R)',':D',':O',':z','<3',':(','B)',';)'],
                   [1,3,5,6,8,15,19,20,24,27,29,30,32,37,39,40,42,48,52,53,57,64],
                   [2,4,5,7,14,18,19,23,26,28,29,31,36,38,39,41,47,51,52,56,63,64],
                   [2,0,4,0,2,0,5,0,3,0,4,0,1,0,4,0,1,0,5,0,3,0]);
     my @wheel3 = ([';P',':)','R)',':(',';P',';)','<3',':(','B)',';)','R)',':P',':O','O_o','R)',':D',':O',':z','<3',':(','B)',';)'],
                   [1,4,5,6,8,14,17,19,22,27,29,31,33,39,41,42,44,52,57,58,63,64],
                   [3,4,5,7,13,16,18,21,26,28,30,32,38,40,41,43,51,56,57,62,63,64],
                   [2,0,4,0,2,0,5,0,3,0,4,0,1,0,4,0,1,0,5,0,3,0]);
     my @payout = ([500,200,75,40,20,10,5,2],
                   [1000,400,150,80,40,20,10,4],
                   [6000,600,225,120,60,30,15,6]);
     my $msg = "";
     my @line = ();
     my %wheel = ();
     $wheel{1} = rand(64)%64;
     for (my $i = 0;$i < 22;$i++) {
          if ($wheel{1} >= $wheel1[1][$i] && $wheel{1} <= $wheel1[2][$i] ) {
               $msg = $msg.$wheel1[0][$i]." ";
               $line[0] = $wheel1[3][$i];
               last;
          } 
     }
     $wheel{2} = rand(64)%64;
     for (my $i = 0;$i < 22;$i++) {
          if ($wheel{2} >= $wheel2[1][$i] && $wheel{2} <= $wheel2[2][$i] ) {
               $msg = $msg.$wheel2[0][$i]." ";
               $line[1] = $wheel2[3][$i];
               last;
          } 
     }
     $wheel{3} = rand(64)%64;
     for (my $i = 0;$i < 22;$i++) {
          if ($wheel{3} >= $wheel3[1][$i] && $wheel{3} <= $wheel3[2][$i] ) {
               $msg = $msg.$wheel3[0][$i];
               $line[2] = $wheel3[3][$i];
               last;
          } 
     }
     my $win = false;
     my $match = false;
     my $symbol = false;
     my $winvalue= 0;
     for (my $i = 0;$i < 3;$i++) {
          $winvalue = $winvalue + $line[$i];
          if ($line[$i] > 0) {
               $symbol = true if ($line[$i] < 4);
               if ($i > 0 && $line[$i-1] == $line[$i]) {
                    $match = true;
               } else {
                    $match = false;
               }
               $win = true;
          } else {
               $win = false;
          }
     }
     my $prize = 0;
     if ($win) {
          $prize = $payout[$arg-1][0] if ($winvalue == 15);
          $prize = $payout[$arg-1][1] if ($match && ($winvalue == 12));
          $prize = $payout[$arg-1][3] if ($match && ($winvalue == 9));
          $prize = $payout[$arg-1][4] if ($match && ($winvalue == 6));
          $prize = $payout[$arg-1][5] if ($match && ($winvalue == 3));
          $prize = $payout[$arg-1][2] if (!$match && !$symbol);
          $prize = $payout[$arg-1][6] if (!$match && $symbol);
          $prize = $payout[$arg-1][7];
          $msg = $msg." Winner! $nick has won $prize tokens!";
          token_add("evepriceinfo",$prize,$nick);
     }
     $irc->yield(privmsg => $where, "$msg");
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

sub help {
     return;
}
