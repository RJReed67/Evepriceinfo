#!/bin/perl

use strict;
use warnings;
use Config::Simple;
use POE qw( Loop::AnyEvent );
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::BotCommand;
use POE::Component::IRC::Plugin::Connector;
use DBI;
use Locale::Currency::Format;
use Log::Log4perl;
use XML::LibXML;
use LWP::Simple qw(!head);
use LWP::UserAgent;
use Time::HiRes qw(time);
use DateTime;
use DateTime::Duration;
use DateTime::Format::MySQL;
use DateTime::Format::DateParse;
use Time::Piece;
use Time::Piece::MySQL;
use Data::Dumper;

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
#my $debug = $ref->{'debug'}->{'value'};
my $debug = 1;
my $install_dir = $ref->{'install_dir'}->{'value'};
my @channels = ($ref->{'channel'}->{'value'});
my $log_conf = $install_dir.$ref->{'log_conf'}->{'value'};
$sth->finish;

Log::Log4perl::init_and_watch($log_conf,60);
my $logger = Log::Log4perl->get_logger;

my @cmds = ();
my %help = ();

push(@cmds,'_start');
push(@cmds,'irc_001');
$sth = $dbh->prepare('SELECT * FROM epi_commands WHERE CmdModule like ?');
$sth->execute('zkb');
$ref = $sth->fetchall_hashref('CmdKey');
foreach ( keys %$ref ) {
     push(@cmds,"irc_botcmd_".$ref->{$_}->{'Command'});
     $help{$ref->{$_}->{'Command'}}=$ref->{$_}->{'HelpInfo'};
}
$sth->finish;
 
$sth = $dbh->prepare('TRUNCATE killcache');
$sth->execute;
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
     $logger->debug("epi_zkb.pl has started!");
     my ($kernel, $heap) = @_[KERNEL ,HEAP];
     $heap->{connector} = POE::Component::IRC::Plugin::Connector->new();
     $irc->plugin_add('Connector' => $heap->{connector} );
     $irc->plugin_add('BotCommand', POE::Component::IRC::Plugin::BotCommand->new(
        Addressed => 0,
        Prefix => '!',
        Method => 'privmsg',
        Ignore_unknown => 1,
        Commands => { %help },
#        Help_sub => \&help,
     ));
     $irc->yield(register => qw(all));
     $irc->yield(connect => { } );
     return;
}

sub irc_001 {
     $irc->yield(join => $_) for @channels;
     $irc->yield(privmsg => $_, '/color blue') for @channels;
     return;
}

sub irc_botcmd_zkb {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $charname) = @_[ARG1, ARG2];
     if (not defined $charname) {
          $irc->yield(privmsg => $where, "/me - Query must be in the form of a single character/corporation name. (e.g. !zkb Ira Warwick)");
          return;
     }
     my $charid = &CharIDLookup($charname);
     if ($charid == false) {
          $irc->yield(privmsg => $where, "/me - There is no $charname in the Eve Universe.");
          return;
     };
     &ZkbLookup($charname,$charid,$where,0);
     return;
}

sub irc_botcmd_zckb {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $corpname) = @_[ARG1, ARG2];
     if (not defined $corpname) {
          $irc->yield(privmsg => $where, "/me - Query must be in the form of a single corporation name. (e.g. !zkb The Romantics)");
          return;
     }
     my $corpid = &CharIDLookup($corpname);
     if ($corpid == -1) {
          $irc->yield(privmsg => $where, "/me - There is not a corporation named $corpname in the Eve Universe.");
          return;
     };
     &ZkbLookup($corpname,$corpid,$where,1);
     return;
}

sub CharIDLookup {
     my $url = "https://api.eveonline.com/eve/CharacterID.xml.aspx?names=$_[0]";
     my $content = get($url);
     my $parser = new XML::LibXML;
     my $doc = $parser->parse_string($content);
     my $xpath="//result/rowset/row/\@characterID";
     my $value = $doc->findvalue($xpath);
     if ($value == 0) {
          return false;
     } else {
          return $value;
     }
}

sub CorpCheck {
     my $url = 'https://api.eveonline.com/eve/CharacterInfo.xml.aspx?&characterId='.$_[0];
     my $content = get($url);
     my $parser = new XML::LibXML;
     my $doc = eval { $parser->parse_string($content) };
     return true if $@;
     my $xpath="//error";
     my $iscorp = $doc->findvalue($xpath);
     $logger->debug("Is ID a corp? $iscorp");
     if ($iscorp > 0) {
          return true;
     } else {
          return false;
     }
}

# ZkbLookup: Args: 0 - Character Name, 1 - Character ID, 2 - IRC Channel to send the msg to, 3 - Corp=1,Char=0.
sub ZkbLookup {
     my $return = &CheckzkbCache($_[1],$_[0],$_[2]);
     if ($return == true) {
          $logger->debug("Found record in killcache for $_[0]");
          return;
     } else {
          $logger->debug("zkillboard lookup: From channel: $_[2] For: $_[0] CharID: $_[1]");
          my $url = "";
          if ($_[3] == 1) {
               $url = "https://zkillboard.com/api/stats/corporationID/$_[1]/xml/";
          } else {
               $url = "https://zkillboard.com/api/stats/characterID/$_[1]/xml/";
          }
          my $browser = LWP::UserAgent->new;
          my $can_accept = HTTP::Message::decodable;
          $browser->agent('Evepriceinfo/Chatbot');
          $browser->from('rjreed67@gmail.com');
          my $content = $browser->get($url,'Accept-Encoding' => $can_accept,);
          if ($content->decoded_content =~ m/html/i) {
               $irc->yield(privmsg => $_[2], "$_[0] was not found at zKillboard.com.");
               return;
          }
          my $parser = new XML::LibXML;
          my $doc = $parser->parse_string($content->decoded_content);
          my $xpath="//row[\@type='count']/\@destroyed";
          my $shipdest = $doc->findvalue($xpath);
          $xpath="//row[\@type='count']/\@lost";
          my $shiplost = $doc->findvalue($xpath);
          $xpath="//row[\@type='isk']/\@destroyed";
          my $iskdest = $doc->findvalue($xpath);
          $xpath="//row[\@type='isk']/\@lost";
          my $isklost = $doc->findvalue($xpath);
          my $eff = sprintf("%.1f",($shipdest/($shipdest+$shiplost))*100);
          my $iskeff = sprintf("%.1f",($iskdest/($iskdest+$isklost))*100);
          my $msg = "/me - $_[0] has ";
          if ($shipdest == 0) {
               $msg = $msg."not destroyed any ships, ";
          } elsif ($shipdest == 1) {
               $msg = $msg."destroyed $shipdest ship, worth ".currency_format('USD', $iskdest, FMT_COMMON)." ";
          } else {
               $msg = $msg."destroyed $shipdest ships, worth ".currency_format('USD', $iskdest, FMT_COMMON)." ";
          }
          $msg = $msg."and ";
          if ($shiplost == 0) {
               $msg = $msg."has not lost any ships.";
          } elsif ($shiplost == 1) {
               $msg = $msg."lost $shiplost ship, worth ".currency_format('USD', $iskdest, FMT_COMMON).".";
          } else {
               $msg = $msg."lost $shiplost ships, worth ".currency_format('USD', $isklost, FMT_COMMON).".";
          }
          $msg .= " Ship Efficiency: $eff% ISK Efficiency: $iskeff%";
          $irc->yield(privmsg => $_[2],$msg);
          my $dt = DateTime::Format::DateParse->parse_datetime($content->header('Expires'));
          my $sth = $dbh->prepare('INSERT INTO killcache SET CharID=?,CharName=?,DestShips=?,DestISK=?,LostShips=?,LostISK=?,DataExpire=?');
          print "Inserting: $_[1]:$_[0]:$shipdest:$iskdest:$shiplost:$isklost:$dt\n" if $debug == 1;
          $sth->execute($_[1],$_[0],$shipdest,$iskdest,$shiplost,$isklost,$dt);
          return;
     }
}

# CheckzkbCache - $Args 0 - CharacterID, 1 - Character Name, 2 - Channel to send msg to. - Returns a value of 1 if valid cache entry is found
sub CheckzkbCache {
     $logger->debug("Called with: $_[0]:$_[1]:$_[2]");
     my $sth = $dbh->prepare('SELECT * FROM killcache WHERE CharID LIKE ?');
     $sth->execute($_[0]);
     my $ref = $sth->fetchrow_hashref();
     if (!$ref) {
          return false;
     } else {
          my $dt1 = DateTime->now(time_zone => "GMT");
          my $dt2 = DateTime::Format::MySQL->parse_datetime($ref->{'DataExpire'});
          my $cmp = DateTime->compare($dt1,$dt2);
          if ($cmp > 0) {
               $sth->finish;
               $sth = $dbh->prepare('DELETE FROM killcache WHERE CharID=?');
               $sth->execute($_[0]);
               $sth->finish;
               return false;
          } else {
               my $shipdest = $ref->{'DestShips'};
               my $iskdest = $ref->{'DestISK'};
               my $shiplost = $ref->{'LostShips'};
               my $isklost = $ref->{'LostISK'};
               my $eff = sprintf("%.1f",($shipdest/($shipdest+$shiplost))*100);
               my $iskeff = sprintf("%.1f",($iskdest/($iskdest+$isklost))*100);
               my $msg = "/me - $_[1] has ";
               if ($shipdest == 0) {
                    $msg = $msg."not destroyed any ships, ";
               } elsif ($shipdest == 1) {
                    $msg = $msg."destroyed $shipdest ship, worth ".currency_format('USD', $iskdest, FMT_COMMON)." ";
               } else {
                    $msg = $msg."destroyed $shipdest ships, worth ".currency_format('USD', $iskdest, FMT_COMMON)." ";
               }
               $msg = $msg."and ";
               if ($shiplost == 0) {
                    $msg = $msg."has not lost any ships.";
               } elsif ($shiplost == 1) {
                    $msg = $msg."lost $shiplost ship, worth ".currency_format('USD', $iskdest, FMT_COMMON).".";
               } else {
                    $msg = $msg."lost $shiplost ships, worth ".currency_format('USD', $isklost, FMT_COMMON).".";
               }
               $msg .= " Ship Efficiency: $eff% ISK Efficiency: $iskeff%";
               $irc->yield(privmsg => $_[2],$msg);
               return true;
          }
     }
}

sub help {
     return;
}
