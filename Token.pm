package Token;

use strict;
use warnings;
use Config::Simple;
use DBI;
use Log::Log4perl;
use Data::Dumper;

use constant {
     true       => 1,
     false      => 0,
};

use Exporter qw(import);
our @EXPORT_OK = qw(token_add token_take);

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
my $debug = $ref->{'debug'}->{'value'};
my @channels = $ref->{'channel'}->{'value'};
my $install_dir = $ref->{'install_dir'}->{'value'};
my $log_conf = $install_dir.$ref->{'log_conf'}->{'value'};
$sth->finish;

Log::Log4perl::init_and_watch($log_conf,60);
my $logger = Log::Log4perl->get_logger;
my $tokenlogger = Log::Log4perl->get_logger("token");

sub token_add {
     my ($nick,$change,$user) = @_;
     my $result;
     my $sth = $dbh->prepare('SELECT * FROM followers WHERE TwitchID LIKE ?');
     $sth->execute($user);
     my $ref = $sth->fetchrow_hashref();
     if (!$ref) {
          $result = false;
     } else {
          my $cur_tokens = $ref->{'Tokens'};
          $sth = $dbh->prepare('UPDATE followers SET Tokens = ?, TTL = ?  WHERE TwitchID like ?');
          $cur_tokens = $cur_tokens + $change;
          $sth->execute($cur_tokens,$ref->{'TTL'},$user);
          $sth->finish;
          $tokenlogger->info("$nick added $change tokens to $user balance");
          $result = true;
     }
     $sth->finish;
     return $result;
}

sub token_take {
     my ($nick,$change,$user) = @_;
     my $result;
     my $sth = $dbh->prepare('SELECT * FROM followers WHERE TwitchID LIKE ?');
     $sth->execute($user);
     my $ref = $sth->fetchrow_hashref();
     if (!$ref) {
          $result = false;
     } else {
          my $cur_tokens = $ref->{'Tokens'};
          $sth = $dbh->prepare('UPDATE followers SET Tokens = ?, TTL = ? WHERE TwitchID like ?');
          $cur_tokens = $cur_tokens - $change;
          $sth->execute($cur_tokens,$ref->{'TTL'},$user);
          $sth->finish;
          $tokenlogger->info("$nick subtracted $change tokens from $user balance");
          $result = true;
     }
     $sth->finish;
     return $result;
}

1;
