#!/bin/perl

use strict;
use warnings;
use Config::Simple;
use DBI;
use Log::Log4perl;
use POSIX qw(strftime);
use Switch;

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
   my $grant=0;
   my @SubDate = split(/-/,$ref->{$key}{SubDate});
   if ($today eq $SubDate[2]) {
      switch ($ref->{$key}{SubLevel}) {
         case [1]    {$grant = 40}
         case [3]    {$grant = 120}
         case [5]    {$grant = 200}
         case [10]   {$grant = 400}
         case [25]   {$grant = 1000}
         case [50]   {$grant = 2000}
         case [100]  {$grant = 4000}
      }
      $sth = $dbh->prepare('CALL AddTokens(?,?)');
      $sth->execute($grant,$key);
      $sth->finish;
      $tokenlogger->info("Subscriber perk: added $grant tokens to $key balance");
   }
}
$logger->info("Ending monthly Subscriber perk scan");
