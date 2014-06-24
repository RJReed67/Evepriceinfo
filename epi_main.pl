#!/bin/perl

use strict;
use warnings;
use Config::Simple;
use Data::Dumper;
use DateTime;
use DBI;
use Log::Log4perl;
use POE;
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::BotCommand;
use POE::Component::IRC::Plugin::Connector;
use Proc::Simple;
use sigtrap qw/handler shutdown normal-signals/;
use lib "/opt/evepriceinfo";
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
my $install_dir = $ref->{'install_dir'}->{'value'};
my @channels = ($ref->{'channel'}->{'value'});
my $log_conf = $install_dir.$ref->{'log_conf'}->{'value'};
$sth->finish;

Log::Log4perl::init_and_watch($log_conf,60);
my $logger = Log::Log4perl->get_logger;

# Varibles for sub-processes

my @subproc;
my @subname;
my @status;
my @subfile;
my @subactive;
$sth = $dbh->prepare('SELECT * FROM ProcStatus ORDER BY ProcKey ASC');
$sth->execute;
while (my @row = $sth->fetchrow_array) {
     $subproc[$row[0]] = Proc::Simple->new();
     $subname[$row[0]] = $row[1];
     $status[$row[0]] = 0;
     $subfile[$row[0]] = $row[2];
     $subactive[$row[0]] = $row[3];
}
$sth->finish;

my @cmds = ();
my %help = ();

push(@cmds,'_start');
push(@cmds,'tick');
push(@cmds,'irc_001');
$sth = $dbh->prepare('SELECT * FROM epi_commands WHERE CmdModule like ?');
$sth->execute('main');
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
     $logger->info("epi_main.pl starting!");
     my ($kernel, $heap) = @_[KERNEL ,HEAP];
     $heap->{connector} = POE::Component::IRC::Plugin::Connector->new();
     $irc->plugin_add('Connector' => $heap->{connector} );
     $heap->{next_alarm_time} = int(time()) + 60;
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
     for (my $count = 1; $count < @subproc; $count++) {
          if ($subactive[$count]) {
               $status[$count] = $subproc[$count]->start("$install_dir/$subfile[$count]");
               $logger->debug("Main starting sub-process: $subfile[$count]. Status: $status[$count]");
          }
     }
     $sth->finish;
     return;
}

sub irc_001 {
     $irc->yield(join => $_) for @channels;
     $irc->yield(privmsg => $_, '/color blue') for @channels;
     return;
}

sub tick {
     my ($kernel,$heap) = @_[KERNEL,HEAP];
     $heap->{next_alarm_time}=int(time())+60;
     $kernel->alarm(tick => $heap->{next_alarm_time});
     $logger->debug("Main timer tick");
     for (my $count = 1; $count < @subproc; $count++) {
          if ($subactive[$count]) {
               $status[$count] = $subproc[$count]->poll();
               if (!$status[$count]) {
                    $logger->info("$subfile[$count] is not running! Attemping restart.");
                    $status[$count] = $subproc[$count]->start("$install_dir/$subfile[$count]");
               }
          }
     }
     return;
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

sub irc_botcmd_reload {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     $arg =~ s/\s+$// if ($arg);
     return if !is_owner($nick);
     my $modsloaded="";
     for (my $count = 1; $count < @subproc; $count++) {
          $modsloaded = $modsloaded.$subname[$count]." " if $subactive[$count];
     }
     if ($arg eq 'list' || $arg eq '') {
          $irc->yield(privmsg => $where, "/me - Modules that can be reloaded:");
          my $msg = "";
          $irc->yield(privmsg => $where, "/me - $modsloaded");
          $irc->yield(privmsg => $where, "/me - command syntax: !reload ModuleName");
     } else {
          if ( $modsloaded =~ /$arg/ ) {
               for (my $count = 1; $count < @subproc; $count++) {
                    if ($subname[$count] =~ $arg) {
                         $logger->info("$nick is restarting module $subname[$count]");
                         $subproc[$count]->kill();
                         sleep 2;
                         $subproc[$count]->start("$install_dir/$subfile[$count]");
                         $irc->yield(privmsg => $where, "/me - $arg has been reloaded.");
                    }
               }
          } else {
               $irc->yield(privmsg => $where, "/me - Invalid module name");
          }
     }
     return;
}

sub irc_botcmd_activate {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     $arg =~ s/\s+$// if ($arg);
     return if !is_owner($nick);
     my $modsunloaded="";
     for (my $count = 1; $count < @subproc; $count++) {
          $modsunloaded = $modsunloaded.$subname[$count]." " if !$subactive[$count];
     }
     if ($arg eq 'list' || $arg eq '') {
          $irc->yield(privmsg => $where, "/me - Modules that can be activated:");
          my $msg = "";
          $irc->yield(privmsg => $where, "/me - $modsunloaded");
          $irc->yield(privmsg => $where, "/me - command syntax: !activate ModuleName");
     } else {
          if ( $modsunloaded =~ /$arg/ ) {
               for (my $count = 1; $count < @subproc; $count++) {
                    if ($subname[$count] =~ $arg) {
                         $logger->info("$nick is starting module $subname[$count]");
                         $status[$count] = $subproc[$count]->start("$install_dir/$subfile[$count]");
                         $subactive[$count] = true;
                         $irc->yield(privmsg => $where, "/me - $arg has been activated.");
                    }
               }
          } else {
               $irc->yield(privmsg => $where, "/me - Invalid module name");
          }
          &updateProcStatus;
     }
     return;
}

sub irc_botcmd_unload {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     $arg =~ s/\s+$// if ($arg);
     return if !is_owner($nick);
     my $modsloaded="";
     for (my $count = 1; $count < @subproc; $count++) {
          $modsloaded = $modsloaded.$subname[$count]." " if $subactive[$count];
     }
     if ($arg eq 'list' || $arg eq '') {
          $irc->yield(privmsg => $where, "/me - Modules that can be unloaded:");
          my $msg = "";
          $irc->yield(privmsg => $where, "/me - $modsloaded");
          $irc->yield(privmsg => $where, "/me - command syntax: !unload ModuleName");
     } else {
          if ( $modsloaded =~ /$arg/ ) {
               for (my $count = 1; $count < @subproc; $count++) {
                    if ($subname[$count] =~ $arg) {
                         $logger->info("$nick is unloading module $subname[$count]");
                         $status[$count] = $subproc[$count]->kill();
                         $subactive[$count] = false;
                         $irc->yield(privmsg => $where, "/me - $arg has been unloaded.");
                    }
               }
          } else {
               $irc->yield(privmsg => $where, "/me - Invalid module name");
          }
          &updateProcStatus;
     }
     return;
}

sub updateProcStatus {
     my $sth = $dbh->prepare('UPDATE ProcStatus SET Active = ? WHERE ProcKey = ?');
     for (my $count = 1; $count < @subproc; $count++) {
          $sth->execute($subactive[$count],$count);
     }
     $sth->finish;
     return;
}

sub shutdown {
     for (my $count = 1; $count < @subproc; $count++) {
          $status[$count] = $subproc[$count]->kill();
     }
     die "Program Ended";
}

sub help {
#     my $nick = (split /!/, $_[ARG0])[0];
#     my ($where, $arg) = @_[ARG1, ARG2];
     my $where = "#rushlock";
     my $sth;
     my $arg = $_[1];
     $arg =~ s/\s+$// if ($arg);
     if ($arg) {
          $sth = $dbh->prepare('SELECT HelpInfo FROM epi_commands WHERE Command like ?');
          $sth->execute($arg);
          my @row = $sth->fetchrow_array;
          $irc->yield(privmsg => $where, "/me - Description: $row[0]") if $row[0];
          $sth->finish;
     } else {
          my %helpmsg = ();
          my $msg = "";
          for (my $count = 1; $count < @subproc; $count++) {
               my $msg = "";
               if ($subactive[$count]) {
                    $msg = $msg.ucfirst($subname[$count])." Commands: ";
                    $sth = $dbh->prepare('SELECT * FROM epi_commands WHERE CmdModule like ? ORDER BY Command ASC');
                    $sth->execute($subname[$count]);
                    $ref = $sth->fetchall_hashref('CmdKey');
                    foreach ( keys %$ref ) {
                         if ($ref->{$_}->{'CmdType'} eq 'info' || $ref->{$_}->{'CmdType'} eq 'custom') {
                              $msg = $msg.$ref->{$_}->{'Command'}.", ";
                              $helpmsg{$ref->{$_}->{'Command'}}=$ref->{$_}->{'HelpInfo'};
                         }
                    }
                    $sth->finish;
                    $msg =~ s/,\s$/\./;
                    $irc->yield(privmsg => $where, "/me - $msg");
               }
          }
          $irc->yield(privmsg => $where, "/me - For more details, use: !help <command>");
          $sth->finish;
     }
     return;
}
