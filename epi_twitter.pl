#!/bin/perl

# epi_twitter.pl - Watches the twitter stream and gives of tokens for tweeting key words.

use strict;
use warnings;
use Config::Simple;
use POE qw( Loop::AnyEvent );
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::Connector;
use DBI;
use Locale::Currency::Format;
use XML::LibXML;
use LWP::Simple qw(!head);
use LWP::UserAgent;
use JSON;
use Time::HiRes qw(time);
use DateTime;
use DateTime::Duration;
use DateTime::Format::MySQL;
use DateTime::Format::DateParse;
use Time::Piece;
use Time::Piece::MySQL;
use Data::Dumper;
use AnyEvent::Twitter::Stream;
use Net::Twitter::Lite::WithAPIv1_1;
use Scalar::Util 'blessed';
use FileHandle;

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
my $sth = $dbh->prepare('SELECT * FROM epi_configuration');
$sth->execute;
my $ref = $sth->fetchall_hashref('setting');
my $twitch_user = $ref->{'twitch_user'}->{'value'};
my $twitch_pwd = $ref->{'twitch_pwd'}->{'value'};
my $twitch_svr = $ref->{'twitch_svr'}->{'value'};
my $twitch_port = $ref->{'twitch_port'}->{'value'};
my $debug = $ref->{'debug'}->{'value'};
my $log_token = $ref->{'log_token'}->{'value'};
my $token_exclude = $ref->{'token_exclude'}->{'value'};
my $tw_following = $ref->{'tw_following'}->{'value'};
my $tw_follow = $ref->{'tw_follow'}->{'value'};
my $tw_pwd = $ref->{'tw_pwd'}->{'value'};;
my $interval = $ref->{'interval'}->{'value'};
my $install_dir = $ref->{'install_dir'}->{'value'};
my $log_dir = $install_dir.$ref->{'log_dir'}->{'value'};
my $token_log = $log_dir.$ref->{'token_filename'}->{'value'};
my @channels = ($ref->{'channel'}->{'value'});
my $consumer_key = $ref->{'tw_consumer_key'}->{'value'};
my $consumer_secret = $ref->{'tw_consumer_secret'}->{'value'};
my $tw_token = $ref->{'tw_token'}->{'value'};
my $tw_token_secret = $ref->{'tw_token_secret'}->{'value'};
$sth->finish;

my $console_log = $log_dir."/console-log.txt";
my $error_log = $log_dir."/error-log.txt";

my $tlog;
my $clog;
my $elog;
my $stdout;
my $stderr;
if ($log_token == 1) {
     $tlog = FileHandle->new(">> $token_log");
     $tlog->autoflush(1);
}
if ($debug == 1) {
     $clog = FileHandle->new("+> $console_log");
     $clog->autoflush(1);
}
open($elog, ">>","$error_log");
$stdout = *STDOUT;
$stderr = *STDERR;
*STDERR = $elog;
*STDOUT = $clog if $debug == 1;
 
my $nt = Net::Twitter::Lite::WithAPIv1_1->new(
     consumer_key    => $consumer_key,
     consumer_secret => $consumer_secret,
     token           => $tw_token,
     token_secret    => $tw_token_secret,
     ssl             => 1,
);

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
                main => [ qw( _start ) ],
        ],
);

my $done = AnyEvent->condvar;

my $listener = AnyEvent::Twitter::Stream->new(
    consumer_key    => $consumer_key,
    consumer_secret => $consumer_secret,
    token           => $tw_token,
    token_secret    => $tw_token_secret,
    method          => "userstream",
    api_url         => "https://userstream.twitter.com/1.1/user.json",
    on_tweet        => sub { 
       my $tweet = shift;
       if ($tweet->{text}) {
          $irc->yield(privmsg => $_, "Tweet from \@$tweet->{user}{screen_name}: $tweet->{text}") for @channels;
       }
    },
    timeout         => 300,
);

my $listener2 = AnyEvent::Twitter::Stream->new(
    consumer_key    => $consumer_key,
    consumer_secret => $consumer_secret,
    token           => $tw_token,
    token_secret    => $tw_token_secret,
    method          => "filter",
    track           => "#Rushlock",
    api_url         => "https://userstream.twitter.com/1.1/user.json",
    timeout         => 300,
    on_tweet        => sub { 
       my $tweet = shift;
       if ($tweet->{text}) {
           my $logtime = Time::Piece->new->strftime('%m/%d/%Y %H:%M:%S');
           my $sth = $dbh->prepare('SELECT a.TwitchID, a.Tokens, b.TTL FROM `followers` a LEFT JOIN `TwitterID2TwitchID` b ON a.TwitchID = b.TwitchID WHERE b.TwitterID IS NOT NULL AND b.TwitterID like ?');
           my $id = "\@".$tweet->{user}{screen_name};
           print $clog "$logtime: Got a tweet from $id.\n" if $debug==1;
           $sth->execute($id) or die "Error: ".$sth->errstr;
           my $rows = $sth->rows;
           if ($rows > 0) {
                my @row=$sth->fetchrow_array();
                my ($twitchid,$tokens,$ttl) = @row;
                print $clog "Twitter user: $id is $twitchid.\n" if $debug==1;
                $sth->finish;
                return if $twitchid =~ m/$token_exclude/i;
                my $dt1 = DateTime::Format::MySQL->parse_datetime($ttl);
                my $dt2 = DateTime->now(time_zone=>'local');
                my $days = ($dt2 - $dt1)->days;
                my $hours = ($dt2 - $dt1)->hours;
                my $duration = ($days * 24) + $hours;
                if ($duration > 18) {
                     print $tlog "$logtime: Giving 5 tokens to \"$twitchid\" for tweeting.\n" if $log_token==1;
                     $tokens = $tokens + 5;
                     $sth = $dbh->prepare('UPDATE followers SET Tokens = ? WHERE TwitchID like ?');
                     $sth->execute($tokens,$twitchid) or die "Error: ".$sth->errstr;
                     $sth->finish;
                     $sth = $dbh->prepare('UPDATE TwitterID2TwitchID SET TTL = NULL WHERE TwitchID like ?');
                     $sth->execute($twitchid) or die "Error: ".$sth->errstr;
                     if ($debug==1) {
                          $irc->yield(privmsg => $_, "5 Tokens given to $twitchid for tweet: $tweet->{text}") for @channels;
                     }
                } else {
                     if ($debug==1) {
                          $irc->yield(privmsg => $_, "Tokens not given to $twitchid for tweet, only $hours hours since last tweet") for @channels;
                     }
                } 
           }
       }
    },
);

my $responder = AnyEvent::Twitter::Stream->new(
    consumer_key    => $consumer_key,
    consumer_secret => $consumer_secret,
    token           => $tw_token,
    token_secret    => $tw_token_secret,
    method          => "filter",
    track           => "#CostOfPLEX",
    api_url         => "https://userstream.twitter.com/1.1/user.json",
    timeout         => 300,
    on_tweet        => sub { 
       my $tweet = shift;
       if ($tweet->{text}) {
           my $screen_name = $tweet->{user}{screen_name};
           my $logtime = Time::Piece->new->strftime('%m/%d/%Y %H:%M:%S');
           print $clog "$logtime: Got a tweet from $screen_name.\n" if $debug==1;
           my $id = $tweet->{user}{id};
           my %hubs = ("Jita",30000142,"Hek",30002053,"Rens",30002510,"Amarr",30002187,"Dodixie",30002659);
           my $price="Market Hub Plex Prices - ";
           while ((my $sysname, my $sysid) = each (%hubs)) {
               $price = $price.$sysname.":".currency_format('USD', &GetXMLValue($sysid,29668,"//sell/min"), FMT_COMMON)." ";
           }
           my $result = eval { $nt->new_direct_message({ text => $price , screen_name => $screen_name }) };
           if ( my $err = $@ ) {
               die $@ unless blessed $err && $err->isa('Net::Twitter::Lite::Error');
               print $elog "HTTP Response Code: ".$err->code."\n";
               print $elog "HTTP Message......: ".$err->message."\n";
               print $elog "Twitter error.....: ".$err->error."\n";
           }
       }
    },
    on_error        => sub {
       my $error = shift;
       warn($error);
       $done->send;
    },
);

$done->recv;

$poe_kernel->run();
 
sub _start {
     my ($kernel, $heap) = @_[KERNEL ,HEAP];
     $heap->{connector} = POE::Component::IRC::Plugin::Connector->new();
     $irc->plugin_add('Connector' => $heap->{connector} );
     $irc->yield(register => qw(all));
     $irc->yield(connect => { } );
     return;
}
