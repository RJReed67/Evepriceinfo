#!/bin/perl

use strict;
use warnings;
use Config::Simple;
use DBI;
use POSIX qw(strftime);
use FileHandle;

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
my $log_dir = $install_dir.$ref->{'log_dir'}->{'value'};
my $log_token = $ref->{'log_token'}->{'value'};
$sth->finish;
my $token_log = $log_dir."/token-log.txt";
my $tlog;
if ($log_token == 1) {
      $tlog = FileHandle->new(">> $token_log");
      $tlog->autoflush(1);
}

$sth = $dbh->prepare('SELECT * FROM Rushlock_TwitchSubs');
$sth->execute;
$ref = $sth->fetchall_hashref('TwitchName');
$sth->finish;
foreach my $key (keys $ref ) {
   my @SubDate = split(/-/,$ref->{$key}{SubDate});
   if ($today eq $SubDate[2]) {
      $sth = $dbh->prepare('CALL AddTokens(200,?)');
      $sth->execute($key);
      $sth->finish;
      my $logtime = strftime "%m/%d/%Y %H:%M:%S", localtime;
      print $tlog "$logtime: EvePriceInfo added 200 tokens to $key balance\n" if $log_token==1;
   }
}
$tlog->close;
