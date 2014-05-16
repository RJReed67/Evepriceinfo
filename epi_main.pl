#!/bin/perl

use strict;
use warnings;
use AnyEvent::Twitter::Stream;
use Config::Simple;
use Data::Dumper;
use DateTime;
use DateTime::Duration;
use DateTime::Format::MySQL;
use DateTime::Format::DateParse;
use DBI;
use FileHandle;
use JSON;
use Locale::Currency::Format;
use Log::Log4perl qw(get_logger :levels);
use LWP::Simple qw(!head);
use LWP::UserAgent;
use Net::Twitter::Lite::WithAPIv1_1;
use POE qw( Loop::AnyEvent );
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::BotCommand;
use POE::Component::IRC::Plugin::Connector;
use POE::Component::IRC::Plugin::Proxy;
use POE::Component::IRC::Plugin::Logger;
use Scalar::Util 'blessed';
use Time::HiRes qw(time);
use Time::Piece;
use Time::Piece::MySQL;
use XML::LibXML;

use constant {
     true	=> 1,
     false	=> 0,
};
 
currency_set('USD','#,###.## ISK',FMT_COMMON);

my $cfg = new Config::Simple('/opt/evepriceinfo/epi.conf'); 
my $DBName = $cfg->param("DBName");
my $DBUser = $cfg->param("DBUser");
my $DBPassword = $cfg->param("DBPassword");

my $dbh = DBI->connect("DBI:mysql:database=$DBName;host=localhost",
                         "$DBUser", "$DBPassword",
                         {'RaiseError' => 1});
$dbh->{mysql_auto_reconnect} = 1;
my $sth = $dbh->prepare('SELECT * FROM epi_config');
$sth->execute;
my $ref = $sth->fetchall_hashref('setting');
#my $twitch_user = $ref->{'twitch_user'}->{'value'};
#my $twitch_pwd = $ref->{'twitch_pwd'}->{'value'};
#my $twitch_svr = $ref->{'twitch_svr'}->{'value'};
#my $twitch_port = $ref->{'twitch_port'}->{'value'};
my $debug = $ref->{'debug'}->{'value'};
#my $twitch_following = $ref->{'twitch_following'}->{'value'};
#my $tw_follow = $ref->{'tw_follow'}->{'value'};
#my $tw_pwd = $ref->{'tw_pwd'}->{'value'};;
my $token_time_interval = $ref->{'token_time_interval'}->{'value'};
my $install_dir = $ref->{'install_dir'}->{'value'};
my $log_dir = $install_dir.$ref->{'log_dir'}->{'value'};
my @channels = ($ref->{'channels'}->{'value'});
my $log_tokens = $ref->{'log_tokens'}->{'value'};
my $token_filename = $log_dir.$ref->{'token_filename'}->{'value'};
my $error_filename = $log_dir.$ref->{'error_filename'}->{'value'};
my $token_exclude = $ref->{'token_exclude'}->{'value'};
my $consumer_key = $ref->{'tw_consumer_key'}->{'value'};
my $consumer_secret = $ref->{'tw_consumer_secret'}->{'value'};
my $tw_token = $ref->{'tw_token'}->{'value'};
my $tw_token_secret = $ref->{'tw_token_secret'}->{'value'};
my $log_chat = $ref->{'log_chat'}->{'value'};
my $token_amt_give = $ref->{'token_amt_give'}->{'value'};
my $twitch_online_url = $ref->{'twitch_online_url'}->{'value'};
my $auto_grant = $ref->{'auto_grant'}->{'value'};
$sth->finish;

my $giveaway_key = 0;
my $giveaway_open = -1;
my $giveaway_title = "";
my $giveaway_threshold = 0;
my $giveaway_autogive = 0;
$sth = $dbh->prepare('SELECT COUNT(*) FROM giveaway');
$sth->execute;
my ($count) = $sth->fetchrow_array;
$sth->finish;
if ($count == 0) {
     $giveaway_key = 0;
     $giveaway_open = -1;
     $giveaway_title = "";
     $giveaway_threshold = 0;
     $giveaway_autogive = 0;
} else {
     $sth = $dbh->prepare('SELECT * FROM giveaway ORDER BY GiveKey DESC LIMIT 1');
     $sth->execute;
     $ref = $sth->fetchrow_hashref();
     if ($ref->{'EndDate'} eq "0000-00-00 00:00:00" ) {
          $giveaway_key = $ref->{'GiveKey'};
          $giveaway_open = 1;
          $giveaway_title = $ref->{'GiveTitle'};
          $giveaway_threshold = $ref->{'Threshold'};
          $giveaway_autogive = $ref->{'AutoGive'};
     } else {
          $giveaway_key = 0;
          $giveaway_open = -1;
          $giveaway_title = "";
          $giveaway_threshold = 0;
          $giveaway_autogive = 0;
     }
}

my $epi_logger =
