#!/bin/perl

use strict;
use warnings;
use Config::Simple;
use DBI;
use Log::Log4perl;
use POSIX qw(strftime);

my $cfg = new Config::Simple('/opt/evepriceinfo/epi.conf'); 
my $DBName = $cfg->param("DBName");
my $DBUser = $cfg->param("DBUser");
my $DBPassword = $cfg->param("DBPassword");

my $today = strftime "%d", localtime;

my $dbh = DBI->connect("DBI:mysql:database=$DBName;host=localhost",
                         "$DBUser", "$DBPassword",
                         {'RaiseError' => 1});
$dbh->{mysql_auto_reconnect} = 1;

my $sth = $dbh->prepare('SELECT * FROM epi_configuration');
$sth->execute;
my $ref = $sth->fetchall_hashref('setting');
my $install_dir = $ref->{'install_dir'}->{'value'};
my $log_conf = $install_dir.$ref->{'log_conf'}->{'value'};
$sth->finish;

Log::Log4perl::init_and_watch($log_conf,60);
my $logger = Log::Log4perl->get_logger;
my $tokenlogger = Log::Log4perl->get_logger("token");

$sth = $dbh->prepare('SELECT * FROM Rushlock_TwitchSubs');
$sth->execute;
$ref = $sth->fetchall_hashref('TwitchName');
$sth->finish;
$logger->info("Starting monthly Subscriber perk scan");
foreach my $key (keys $ref ) {
   my @SubDate = split(/-/,$ref->{$key}{SubDate});
   if ($today eq $SubDate[2]) {
      $sth = $dbh->prepare('CALL AddTokens(200,?)');
      $sth->execute($key);
      $sth->finish;
      $tokenlogger->info("Subscriber perk: added 200 tokens to $key balance");
   }
}
$logger->info("Ending monthly Subscriber perk scan");
