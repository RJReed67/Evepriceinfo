package EPIUser;

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
our @EXPORT_OK = qw(is_subscriber is_authorized is_owner);

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
my $install_dir = $ref->{'install_dir'}->{'value'};
my $log_conf = $install_dir.$ref->{'log_conf'}->{'value'};
$sth->finish;

Log::Log4perl::init_and_watch($log_conf,60);
my $logger = Log::Log4perl->get_logger;

# is_subscriber returns false is the user isn't found in the Rushlock_TwitchSubs table, or
# returns the subscriber's subscription level.

sub is_subscriber {
     my $user = $_[0];
     my $result;
     my $sth = $dbh->prepare('SELECT * FROM Rushlock_TwitchSubs WHERE TwitchName LIKE ?');
     $sth->execute($user);
     my $ref = $sth->fetchrow_hashref();
     if (!$ref) {
          $result = false;
          $logger->debug("$user is not a subscriber.")
     } else {
          $result = $ref->{'SubLevel'};
          $logger->debug("$user is a subscriber with a level of $result.")
     }
     $sth->finish;
     return $result;
}

sub is_authorized {
     my $user = $_[0];
     my $result;
     my $sth = $dbh->prepare('SELECT * FROM AuthorizedUsers WHERE TwitchID LIKE ?');
     $sth->execute($user);
     my $ref = $sth->fetchrow_hashref();
     if (!$ref) {
          $result = false;
          $logger->debug("$user is not authorized.")
     } else {
          $result = true;
          $logger->debug("$user is authorized.")
     }
     $sth->finish;
     return $result;    
}

sub is_owner {
     my $nick = $_[0];
     my $result;
     my $sth = $dbh->prepare('SELECT * FROM AuthorizedUsers WHERE TwitchID LIKE ? AND Owner = 1');
     $sth->execute($nick);
     my $ref = $sth->fetchrow_hashref();
     if (!$ref) {
          $result = false;
          $logger->debug("$nick is not an owner.")
     } else {
          $result = $ref->{'Owner'};
          $logger->debug("$nick is an owner.")
     }
     $sth->finish;
     return $result;         
}

1;