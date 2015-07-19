#!/bin/perl

use strict;
use warnings;
use Config::Simple;
use Data::Dumper;
#use DateTime;
#use DateTime::Duration;
#use DateTime::Format::MySQL;
#use DateTime::Format::DateParse;
use DBI;
use List::Util qw/sum/;
use Log::Log4perl;
use POE;
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::BotCommand;
use POE::Component::IRC::Plugin::Connector;
use lib "/opt/evepriceinfo";
use Token qw(token_add token_take);
use EPIUser qw(is_subscriber is_authorized is_owner is_oper);

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

my $matchid = 0;
my $match_open = 0;
$sth = $dbh->prepare("SELECT COUNT(*) FROM `Match`");
$sth->execute;
my ($count) = $sth->fetchrow_array;
$sth->finish;
if ($count == 0) {
     $matchid = 0;
} else {
     $sth = $dbh->prepare('SELECT * FROM `Match` ORDER BY MatchID DESC LIMIT 1');
     $sth->execute;
     $ref = $sth->fetchrow_hashref();
     if (!$ref->{'MatchWinner'}) {
          $matchid = $ref->{'MatchID'};
          $match_open = 1
     } else {
          $matchid = 0;
          $match_open = 0;
     }
}

my @teamname = ("A","B","C","D","E","F");
 
my @cmds = ();
my %help = ();

push(@cmds,'_start');
push(@cmds,'irc_botcmd_matchclose');
$sth = $dbh->prepare('SELECT * FROM epi_commands WHERE CmdModule like ?');
$sth->execute('wwematch');
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

sub irc_botcmd_match {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     $arg =~ s/\s+$//;
     if (is_authorized($nick)) {
        if (not defined $arg) {
           $irc->yield(privmsg => $where, "/me - No Wrestler Names/Teams found in command. Names/Teams should be separated by a :");
           return;
        }
        my @teams = split(':', $arg);
        my $numofteams = scalar @teams;
        if (scalar @teams < 2) {
           $irc->yield(privmsg => $where, "/me - Not enough Names/Teams. Needs at least 2 names/teams");
           return;
        } elsif (scalar @teams > 6) {
           $irc->yield(privmsg => $where, "/me - Too many Names/Teams. Needs less than 6 names/teams");
           return;
        }
        for (my $count = scalar @teams; $count < 6; $count = $count + 1) {
           $teams[$count]="";
        }
        $sth = $dbh->prepare('INSERT INTO `Match` SET MatchTime=NOW(),NumOfSides=?,A=?, B=?, C=?, D=?, E=?, F=?');
        $sth->execute($numofteams,$teams[0],$teams[1],$teams[2],$teams[3],$teams[4],$teams[5]);
        $sth->finish;
        $irc->yield(privmsg => $where, "/me - New match is going to start. You have 1 minute to place a wager!");
        $irc->yield(privmsg => $where, "/me - To place a wager use: !wager #ofTokens Side - where Side is one of the following letters:");
        for ($count = 0; $count < $numofteams; $count = $count + 1) {
           $irc->yield(privmsg => $where, "/me - Side $teamname[$count] is $teams[$count].");
        }
        $irc->yield(privmsg => $where, "/me - Once all wagering is completed. The payout ratios will be posted.");
        $match_open = true;
        my ($kernel, $self) = @_[KERNEL, OBJECT];
        $kernel->delay_set(irc_botcmd_matchclose => 60, 'evepriceinfo!evepriceinfo@evepriceinfo.twitch.tv','#rushlock','');
     }
     return;
}

sub irc_botcmd_matchclose {
     my $nick = (split /!/, $_[ARG0])[0];
     my $where = $_[ARG1];
     if (!is_authorized($nick)) {
          return;
     }
     $irc->yield(privmsg => $where, "/me - Wagering is now closed. No more !wager commands will be accepted.");
     $match_open = false;
     my $sth = $dbh->prepare('SELECT MatchID,NumOfSides FROM `Match` ORDER BY MatchID DESC LIMIT 1');
     $sth->execute();
     my ($matchid,$numofsides) = $sth->fetchrow_array;
     my $pool = $dbh->selectrow_array("SELECT SUM(WagerAmt) FROM MatchWagers WHERE MatchID=\"$matchid\"");
     my $rake = int (($pool * .15) + .5);
     $pool = $pool - $rake;
     my @wageronside;
     my @odds;
     $irc->yield(privmsg => $where, "/me - Total Payout Pool: $pool");
     $irc->yield(privmsg => $where, "/me - Here are the payout ratios:");
     for (my $z = 0; $z < $numofsides; $z = $z + 1) {
          $wageronside[$z] = $dbh->selectrow_array("SELECT SUM(WagerAmt) FROM MatchWagers WHERE MatchID=\"$matchid\" AND WagerOnWho=\"$teamname[$z]\"");
          if (!$wageronside[$z]) {
               $wageronside[$z] = 0;
               $odds[$z] = 0;
          } else {
               $odds[$z] = ($pool - $wageronside[$z]) / $wageronside[$z];
          }
          $sth = $dbh->prepare('UPDATE MatchWagers SET Odds=? WHERE WagerOnWho=? AND MatchID=?');
          $sth->execute($odds[$z],$teamname[$z],$matchid);
          if ($odds[$z] == 0) {
               $irc->yield(privmsg => $where, "Side $teamname[$z] - No bets");
          } else {
               my $tmp = "Bet * ".sprintf("%.3f",$odds[$z]+1);
#               my $tmp = &dec2frac($odds[$z]);
               $irc->yield(privmsg => $where, "Side $teamname[$z] - $tmp");
          }
     }
     $irc->yield(privmsg => $where, "/me - Good Luck Everyone!");
     $sth = $dbh->prepare('UPDATE `Match` SET TotalPool=?,Rake=? WHERE MatchID=?');
     $sth->execute($pool,$rake,$matchid);
     return;
}

sub irc_botcmd_wager {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     $arg =~ s/\s+$//;
     if ($match_open != true) {
          return;
     }
     if ($arg !~ /^\d+\s[aAbBcCdDeEfF]$/) {
          $irc->yield(privmsg => $where, "/me - $nick, The wager must be in the format !wager #ofTokens Side");
          return;
     }
     my ($wager, $onwho) = split(/ /,$arg);
     if ($wager !~ /^\d+$/) {
          $irc->yield(privmsg => $where, "/me - $nick, The number of tokens must be a number!");
          return;
     }
     if ($wager < 10) {
          $irc->yield(privmsg => $where, "/me - $nick, Wager must be 10 or more tokens.");
          return;
     }
     my $sth = $dbh->prepare('SELECT MatchID FROM `Match` ORDER BY MatchID DESC LIMIT 1');
     $sth->execute();
     ($matchid) = $sth->fetchrow_array;
     my $currentwager = $dbh->selectrow_array("SELECT WagerID FROM MatchWagers WHERE TwitchID = \"$nick\" AND MatchID = \"$matchid\"");
     if ($currentwager) {
          $irc->yield(privmsg => $where, "/me - $nick, you have already made a wager for this match!");
          return;
     }
     my $max = $dbh->selectrow_array("SELECT Tokens FROM followers WHERE TwitchID = \"$nick\"");
     if ($wager > $max) {
          $irc->yield(privmsg => $where, "/me - $nick, you do not have $arg tokens!");
          return;
     }
     $onwho = uc $onwho;
     $sth = $dbh->prepare("INSERT INTO MatchWagers SET MatchID=?,TwitchID=?,WagerOnWho=?,WagerAmt=?");
     $sth->execute($matchid,$nick,$onwho,$wager);
     token_take("evepriceinfo",$wager,$nick);
     $irc->yield(privmsg => $where, "/me - $nick Your wager for $wager tokens has been made. Good Luck!");
     return;
}

sub irc_botcmd_winner {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     if (is_authorized($nick)) {
          if ($arg !~ /^[aAbBcCdDeEfF]$/) {
               $irc->yield(privmsg => $where, "/me - Winner must be A-F.");
               return;
          }
          $arg =~ s/\s+$//;
          $arg = uc $arg;
          my $sth = $dbh->prepare('SELECT * FROM `Match` ORDER BY MatchID DESC LIMIT 1');
          $sth->execute();
          my @ref = $sth->fetchrow_array();
          my %h;
          @h{'A' .. 'F'} = (3 .. 8);
          my $winner = $ref[ $h{$arg} ];
          $irc->yield(privmsg => $where, "/me - The Winner is $winner!");
          $sth = $dbh->prepare("UPDATE `Match` SET MatchWinner=? WHERE MatchID=?");
          $sth->execute($arg,$matchid);
          $sth = $dbh->prepare("SELECT WagerID,MatchID,TwitchID,WagerAmt,Odds FROM MatchWagers WHERE MatchID = ? AND WagerOnWho = ?");
          $sth->execute($matchid,$arg);
          while ( my @row = $sth->fetchrow_array() ) {
               my ($wagerid, $matchid, $twitchid, $wager, $odds) = @row;
               my $winnings = $wager + int (($wager * $odds) + .5);
               token_add("evepriceinfo",$winnings,$twitchid);
               $irc->yield(privmsg => $where, "/me - $twitchid you won $winnings tokens. Congrats!");
          }
          $irc->yield(privmsg => $where, "/me - The Winners have been paid!");
     }
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

sub dec2frac {
    my $d = shift;

    my $df  = 1;
    my $top = 1;
    my $bot = 1;

    while ($df != $d) {
      if ($df < $d) {
        $top += 1;
      }
      else {
         $bot += 1;
         $top = int($d * $bot);
      }
      $df = $top / $bot;
   }
   return "$top/$bot";
}

sub help {
     return;
}