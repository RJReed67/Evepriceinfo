#!/bin/perl

use strict;
use warnings;
use Config::Simple;
use POE;
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::BotCommand;
use POE::Component::IRC::Plugin::Connector;
use DBI;
use Locale::Currency::Format;
use XML::LibXML;
use Log::Log4perl;
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
my $tw_following = $ref->{'tw_following'}->{'value'};
my $tw_follow = $ref->{'tw_follow'}->{'value'};
my $tw_pwd = $ref->{'tw_pwd'}->{'value'};;
my $install_dir = $ref->{'install_dir'}->{'value'};
my @channels = ($ref->{'channel'}->{'value'});
my $log_conf = $install_dir.$ref->{'log_conf'}->{'value'};
$sth->finish;

Log::Log4perl::init_and_watch($log_conf,60);
my $logger = Log::Log4perl->get_logger;
 
my @cmds = ();
my %help = ();

push(@cmds,'_start');
$sth = $dbh->prepare('SELECT * FROM epi_commands WHERE CmdModule like ?');
$sth->execute('eve');
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
        WhoJoiners => 0,
) or die "Error: $!";

POE::Session->create(
        package_states => [
                main => [ @cmds ],
        ],
);

$poe_kernel->run();
 
sub _start {
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
     return;
}

sub irc_botcmd_yield {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     if (!$arg) {
          return -1;
     }
     $arg =~ s/\s+$//;
     my @mins=("Tritanium","Pyerite","Mexallon","Isogen","Nocxium","Zydrine","Megacyte","Morphite");
     my $sth = $dbh->prepare('SELECT * FROM refineInfo WHERE refineItem LIKE ?');
     $sth->execute($arg);
     my $ref = $sth->fetchrow_hashref();
     if (!$ref) {
        $irc->yield(privmsg => $where, "/me - $arg is not a valid Item.");
        return -1;
     }
     my %items = %$ref;
     my $msg = "/me - $arg yields: ";
     foreach my $mineral (@mins) {
          my $amt = $ref->{$mineral};
          if ($amt > 0) {
               $msg = $msg.$mineral.":".$amt." ";
          }
     }
     $msg = $msg."for every ".$ref->{'batchsize'}." units refined.";
     $sth->finish;
     $irc->yield(privmsg => $where, $msg);
     return;
}
 
sub irc_botcmd_ice {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     $arg =~ s/\s+$//;
     my @mins=("Heavy Water","Helium Isotopes","Hydrogen Isotopes","Nitrogen Isotopes","Oxygen Isotopes","Liquid Ozone","Strontium Calthrates");
     my $sth = $dbh->prepare('SELECT * FROM icerefine WHERE icetype LIKE ?');
     $sth->execute($arg);
     my $ref = $sth->fetchrow_hashref();
     if (!$ref) {
        $irc->yield(privmsg => $where, "/me - $arg is not a valid Ice Type.");
        return -1;
     }
     my %items = %$ref;
     my $msg = "/me - $arg yields: ";
     foreach my $mineral (@mins) {
          my $amt = $ref->{$mineral};
          if ($amt > 0) {
               $msg = $msg.$mineral.":".$amt." ";
          }
     }
     $msg = $msg."for every ".$ref->{'RefineSize'}." unit refined.";
     $sth->finish;
     $irc->yield(privmsg => $where, $msg);
     return;
}

sub irc_botcmd_plex {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     $arg =~ s/\s+$//;
     if (not defined $arg) {
          $irc->yield(privmsg => $where, "/me - Query must have in a SystemName, Region RegionName, or Hub. (e.g. !plex Hub)");
          return;
     }
     if ($arg eq "?") {
          $irc->yield(privmsg => $where, "/me - PLEX is an in-game item, that can be purchased with real money or in-game currency called ISK. PLEX gives you an extra 30 days of game time on your Eve Online account.");
          return;
     }
     $arg = lc($arg);
     if ($arg eq "hub") {
          my %hubs = ("Jita",30000142,"Hek",30002053,"Rens",30002510,"Amarr",30002187,"Dodixie",30002659);
          my $price="";
          while ((my $sysname, my $sysid) = each (%hubs)) {
               $price = $price.$sysname.":".currency_format('USD', &GetXMLValue($sysid,29668,"//sell/min"), FMT_COMMON)." ";
          }
          $irc->yield(privmsg => $where, "/me - Market Hub Prices for PLEX - $price");
     } elsif ($arg =~ /region/) {
          my ($cmd, $regname) = split(' ', $arg, 2);
          $regname =~ s/\s+$//;
          if (not defined $regname) {
               $irc->yield(privmsg => $where, "/me - Query must be in the form of Region RegionName. (e.g. !plex Region Lonetrek)");
               return;
          }
          my $regid = &RegionLookup($regname,$where);
          return if ($regid == -1);
          my $maxprice = &GetXMLValueReg($regid,29668,"//sell/min");
          if ($maxprice != 0) {
               $maxprice = currency_format('USD', $maxprice, FMT_COMMON);
               $irc->yield(privmsg => $where, "/me - PLEX is selling for $maxprice in $regname region.");
          } else {
               $irc->yield(privmsg => $where, "/me - There is no PLEX for sell in $regname region.");
          }
     } else {
     my $sysid = &SystemLookup($arg,$where);
     if ($sysid == -1) {
          return;
     };
          my $maxprice = &GetXMLValue($sysid,29668,"//sell/min");
          if ($maxprice != 0) {
               $maxprice = currency_format('USD', $maxprice, FMT_COMMON);
               $irc->yield(privmsg => $where, "/me - PLEX is selling for $maxprice in $arg.");
          } else {
               $irc->yield(privmsg => $where, "/me - There is no PLEX for sell in $arg.");
          }
     }
     return;
}

sub irc_botcmd_pc {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     my ($sysname, $itemname) = split(' ', $arg, 2);
     if (not defined $itemname) {
          $irc->yield(privmsg => $where, "/me - Query must be in the form of SystemName and ItemName. (e.g. !pc Rens Punisher)");
          return;
     }
     $itemname =~ s/\s+$//;
     my $sysid = &SystemLookup($sysname,$where);
     if ($sysid == -1) { return; };
     my $itemid = &ItemLookup($itemname,$where);
     if ($itemid == -1) { return; };
     my $maxprice = &GetXMLValue($sysid,$itemid,"//sell/min");
     if ($maxprice != 0) {
          $maxprice = currency_format('USD', $maxprice, FMT_COMMON);
          $irc->yield(privmsg => $where, "/me - $itemname is selling for $maxprice in $sysname.");
     } else {
          $irc->yield(privmsg => $where, "/me - There is no $itemname for sell in $sysname.");
     }
     return;
}
 
sub irc_botcmd_rpc {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     my ($regname, $itemname) = split(',', $arg, 2);
     $itemname =~ s/\s+$//;
     if (not defined $itemname) {
          $irc->yield(privmsg => $where, "/me - Query must be in the form of RegionName,ItemName. (e.g. !rpc Lonetrek,Punisher)");
          return;
     }
     my $regid = &RegionLookup($regname,$where);
     if ($regid == -1) { return; };
     my $itemid = &ItemLookup($itemname,$where);
     if ($itemid == -1) { return; };
     my $maxprice = &GetXMLValueReg($regid,$itemid,"//sell/min");
     if ($maxprice != 0) {
          $maxprice = currency_format('USD', $maxprice, FMT_COMMON);
          $irc->yield(privmsg => $where, "/me - $itemname is selling for $maxprice in $regname region.");
     } else {
          $irc->yield(privmsg => $where, "/me - There is no $itemname for sell in $regname region.");
     }
     return;
}
 
sub irc_botcmd_pca {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     $arg =~ s/\s+$//;
     my ($sysname, $itemname) = split(' ', $arg, 2);
     if (not defined $itemname) {
          $irc->yield(privmsg => $where, "/me - Query must be in the form of SystemName and ItemName. (e.g. !pca Rens Punisher)");
          return;
     }
     my $sysid = &SystemLookup($sysname,$where);
     if ($sysid == -1) { return; };
     my $itemid = &ItemLookup($itemname,$where);
     if ($itemid == -1) { return; };
     my $avgprice = &GetXMLValue($sysid,$itemid,"//all/avg");
     my $volume = &GetXMLValue($sysid,$itemid,"//all/volume");
     if ($avgprice != 0) {
          $avgprice = currency_format('USD', $avgprice, FMT_COMMON);
          $irc->yield(privmsg => $where, "/me - $itemname has sold $volume units in the past 24 hours, at an average price of $avgprice in $sysname.");
     } else {
          $irc->yield(privmsg => $where, "/me - There is no $itemname for sell in $sysname.");
     }
     return;
}
 
sub irc_botcmd_hpc {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     $arg =~ s/\s+$//;
     my %hubs = ("Jita",30000142,"Hek",30002053,"Rens",30002510,"Amarr",30002187,"Dodixie",30002659);
     my $itemid = &ItemLookup($arg,$where);
     if ($itemid == -1) { return; };
     my $price="";
     while ((my $sysname, my $sysid) = each (%hubs)) {
          my $hprice = &GetXMLValue($sysid,$itemid,"//sell/min");
          if ( $hprice > 0) {
               $price = $price.$sysname.":".currency_format('USD', $hprice, FMT_COMMON)." ";
          }
     }
     if ($price ne "") {
          $irc->yield(privmsg => $where, "/me - Market Hub Prices for $arg - $price");
     } else {
          $irc->yield(privmsg => $where, "/me - $arg is not available at any market hub.");
     }
}
 
sub irc_botcmd_server {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $arg) = @_[ARG1, ARG2];
     my $url = get('https://api.eveonline.com/server/ServerStatus.xml.aspx');
     my $parser = new XML::LibXML;
     my $doc = $parser->parse_string($url);
     my $xpath="//result/onlinePlayers/text()";
     my $value = $doc->findnodes($xpath);
     $xpath="//currentTime/text()";
     my $time = $doc->findvalue($xpath);
     $xpath="//result/serverOpen/text()";
     my $online = $doc->findnodes($xpath);
     if ($online =~ /True/) {
          $irc->yield(privmsg => $where, "/me - Server is Online with $value Players. Server Time: $time");
     } else {
          $irc->yield(privmsg => $where, "/me - Server is currently Offline. Server Time: $time");
     }
     return;
}

sub irc_botcmd_cinfo {
     my $nick = (split /!/, $_[ARG0])[0];
     my ($where, $corpname) = @_[ARG1, ARG2];
     if (not defined $corpname) {
          $irc->yield(privmsg => $where, "/me - Query must be in the form of a single corporation name. (e.g. !cinfo The Romantics)");
          return;
     }
     my $corpid = &CharIDLookup($corpname);
     if ($corpid == -1) {
          $irc->yield(privmsg => $where, "/me - There is not a corporation named $corpname in the Eve Universe.");
          return;
     };
     &CorpLookup($corpname,$corpid,$where);
     return;
}

sub CorpLookup {
     my $url = "https://api.eveonline.com/corp/CorporationSheet.xml.aspx?corporationID=$_[1]";
     my $content = get($url);
     if (not defined $content) {
          $irc->yield(privmsg => $_[2], "/me - $_[0] was not found.");
          return;
     }    
     my $parser = new XML::LibXML;
     my $doc = $parser->parse_string($content);
     my $xpath="//ceoName";
     my $ceoname = $doc->findvalue($xpath);
     $xpath="//memberCount";
     my $memcount = $doc->findvalue($xpath);
     $xpath="//stationName";
     my $station = $doc->findvalue($xpath);
     $irc->yield(privmsg => $_[2], "/me - $_[0] - CEO: $ceoname - Members: $memcount - HQ: $station");
     return;
}

sub GetXMLValue {
     my $url = "http://api.eve-central.com/api/marketstat?usesystem=$_[0]&typeid=$_[1]";
     my $parser = new XML::LibXML;
     my $doc = eval { $parser->parse_file("$url") };
     return 0 if $@;
     my $xpath="//sell/min";
     my $value = $doc->findvalue($_[2]);
     return $value;
}
 
sub GetXMLValueReg {
     my $url = "http://api.eve-central.com/api/marketstat?regionlimit=$_[0]&typeid=$_[1]";
     my $parser = new XML::LibXML;
     my $doc = eval { $parser->parse_file("$url") };
     return 0 if $@;
     my $xpath="//sell/min";
     my $value = $doc->findvalue($_[2]);
     return $value;
}
 
sub ItemLookup {
     my $sth = $dbh->prepare('SELECT typeID as ItemID FROM invTypes WHERE typeName LIKE ?');
     $sth->execute($_[0]);
     my $ref = $sth->fetchrow_hashref();
     if (!$ref) {
        $irc->yield(privmsg => $_[1], "/me - $_[0] is not a valid Item.");
        return -1;
     }
     my $itemid = $ref->{'ItemID'};
     $sth->finish;
     return $itemid;
}
 
sub SystemLookup {
     my $sth = $dbh->prepare('SELECT SystemID FROM systemids WHERE SystemName LIKE ?');
     $sth->execute($_[0]);
     my $ref = $sth->fetchrow_hashref();
     if (!$ref) {
        $irc->yield(privmsg => $_[1], "/me - $_[0] is not a valid System.");
        return -1;
     }
     my $sysid = $ref->{'SystemID'};
     $sth->finish;
     return $sysid;
}
 
sub RegionLookup {
     my $sth = $dbh->prepare('SELECT RegionID FROM regionids WHERE RegionName LIKE ?');
     $sth->execute($_[0]);
     my $ref = $sth->fetchrow_hashref();
     if (!$ref) {
        $irc->yield(privmsg => $_[1], "/me - $_[0] is not a valid Region.");
        return -1;
     }
     my $regid = $ref->{'RegionID'};
     $sth->finish;
     return $regid;
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
