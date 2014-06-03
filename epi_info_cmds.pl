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
use Data::Dumper;

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
my $interval = $ref->{'interval'}->{'value'};
my $install_dir = $ref->{'install_dir'}->{'value'};
my @channels = ($ref->{'channel'}->{'value'});
my $log_conf = $install_dir.$ref->{'log_conf'}->{'value'};
$sth->finish;

Log::Log4perl::init_and_watch($log_conf,60);
my $logger = Log::Log4perl->get_logger;
my $tokenlogger = Log::Log4perl->get_logger("token");

my $offline_timer = 0;
my $chatlines = 0;
my $online_timer = 0;
 
my @cmds = ();
my %help = ();
my %rep = ();

push(@cmds,'_start');
push(@cmds,'irc_public');
push(@cmds,'irc_botcmd_info');
$sth = $dbh->prepare('SELECT * FROM epi_commands WHERE CmdType like ?');
$sth->execute("info");
$ref = $sth->fetchall_hashref('CmdKey');
foreach ( keys %$ref ) {
     my $key = $ref->{$_}->{'Command'};
     my $helptxt = $ref->{$_}->{'HelpInfo'};
     my $repeat = $ref->{$_}->{'Repeat'};
     my $cycletime = $ref->{$_}->{'CycleTime'};
     my $lines = $ref->{$_}->{'NumOfChatLines'};
     $help{$key}{info}="$helptxt";
     $help{$key}{handler}="irc_botcmd_info";
     $rep{$key}{repeat}="$repeat";
     $rep{$key}{timer}="$cycletime";
     $rep{$key}{lines}="$lines";
     $rep{$key}{count}=0;
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
     foreach ( keys %rep ) {
          if ($rep{$_}{repeat} == 1) {
               my $cmdname = $_;
               my $cmdtimer = $rep{$_}{timer};
               $kernel->delay(irc_botcmd_info => $cmdtimer,('evepriceinfo!evepriceinfo@evepriceinfo.twitch.tv','#rushlock',$cmdname));
          }
     }
     return;
}

sub irc_public {
     my $nick = (split /!/, $_[ARG0])[0];
     my $msg = $_[ARG2];
     foreach ( keys %rep ) {
          if ($rep{$_}{repeat} == true) {
               $rep{$_}{count}++ if ($rep{$_}{repeat} == true);
               $logger->debug("$_ line counter: $rep{$_}{count}");
          }
     }
}

sub irc_botcmd_info {
     my ($kernel, $heap) = @_[KERNEL ,HEAP];
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, 14];
     if ($nick =~ m/evepriceinfo/) {
          $arg = $_[ARG2];
          $logger->debug("Command $arg called by auto repeat.");
          $logger->debug("$arg counter: $rep{$arg}{count}");
          if ($rep{$arg}{repeat} == true && $rep{$arg}{count} >= $rep{$arg}{lines}) {
               $rep{$arg}{count} = 0;
               $kernel->delay_add('irc_botcmd_info' => $rep{$arg}{timer}, $_[ARG0], $_[ARG1], $arg);
          } else {
               $kernel->delay_add('irc_botcmd_info' => $rep{$arg}{timer}, $_[ARG0], $_[ARG1], $arg);
               return;
          }
     }
     $arg =~ s/\s+$//;
     my $sth = $dbh->prepare('SELECT * FROM epi_info_cmds WHERE CmdName LIKE ?');
     $sth->execute($arg);
     my $ref = $sth->fetchrow_hashref();
     $irc->yield(privmsg => $where, "/me - ".$ref->{'DisplayInfo'});
     $sth->finish;
     return;
}

sub help {
     return;
}
