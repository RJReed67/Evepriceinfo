package EPIBlackJack;

use strict;
use warnings;
use Config::Simple;
use DBI;
use List::Util qw(shuffle);
use Log::Log4perl;
use Data::Dumper;
use lib "/opt/evepriceinfo";
use Token qw(token_add token_take);

use constant {
     true       => 1,
     false      => 0,
};

use Exporter qw(import);
our @EXPORT_OK = qw(newshoe deal valuehand show_game givecard eval_game get_curr_game);

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

sub encodedeck {
     my $deck = shift;
     my $dbshoe = "";
     for my $card (@{$deck}) {
          $dbshoe = $dbshoe.$card;
     }
     return $dbshoe;
}

sub valuehand {
     my @hand = $_[0] =~ m/../g;
     foreach my $card (0 .. $#hand) {
          $hand[$card] =~ s/[HDCS]//;
          $hand[$card] =~ s/[TJQK]/10/;
          $hand[$card] =~ s/A/11/;
     }
     @hand = sort {$a <=> $b} @hand;
     my $value = 0;
     foreach my $card (0 .. $#hand) {
          if ($card > 0) {
               if ($hand[$card] == 11 && $hand[($card-1)] == 11) {
                    $hand[($card-1)] = 1;
                    $value = $value - 10;
                    if ($value >= 11) {
                         $hand[$card] = 1;
                    }
               } elsif ($value >= 11 && $hand[$card] == 11) {
                    $hand[$card] = 1;
               }
          }
          $value += $hand[$card];
     }
     return $value;
}

sub show_game {
     my $player = $_[0];
     my $holdcard = $_[1];
     my @curr_game = ();
     my $gamemsg;
     $sth = $dbh->prepare('SELECT * FROM BJGame WHERE TwitchID = ?');
     $sth->execute($player);
     @curr_game = $sth->fetchrow_array;
     $sth->finish;
     my @playerhand = ( $curr_game[3] =~ m/../g );
     my @dealerhand = ( $curr_game[4] =~ m/../g );
     $gamemsg = "$player: ";
     foreach my $card (@playerhand) {
          $gamemsg = $gamemsg.$card." ";
     }
     $gamemsg = $gamemsg."(".valuehand($curr_game[3]).") "."Dealer: ";
     my $i;
     for ($i = 0; $i <= $#dealerhand; $i++) {
          if ($i == $#dealerhand && $holdcard == 0) {
               $gamemsg = $gamemsg."??";
          } else {
               $gamemsg = $gamemsg.$dealerhand[$i]." ";
          }
     }
     if ($holdcard != 0) {
          $gamemsg = $gamemsg."(".valuehand($curr_game[4]).") ";
     }
     return $gamemsg;
}

sub eval_game {
     # called when the player has busted or stands.
     my $player = $_[0];
     my $where = $_[1];
     $sth = $dbh->prepare('SELECT * FROM BJGame WHERE TwitchID = ?');
     $sth->execute($player);
     my @curr_game = $sth->fetchrow_array;
     $sth->finish;
     my $gamemsg = "";
     if (valuehand($curr_game[3]) > 21) {
          $gamemsg = show_game($player,1)." ".$player." Busted!";
          $sth = $dbh->prepare('UPDATE BJGame SET Hand = NULL, Dealer = NULL, Bet = NULL, TTL = NULL WHERE TwitchID = ?');
          $sth->execute($player);
          $sth->finish;
          return $gamemsg;
     }
     my @shoe = ( $curr_game[2] =~ m/../g );
     my $dbshoe = "";
     while (valuehand($curr_game[4]) < 17) {
          last if (valuehand($curr_game[3]) == 21 && length($curr_game[3]) == 4);
          $curr_game[4] = $curr_game[4].shift @shoe;
     }
     foreach my $card (@shoe) {
          $dbshoe = $dbshoe.$card;
     }
     $sth = $dbh->prepare('UPDATE BJGame SET Shoe = ?, Dealer = ?, TTL = NULL WHERE TwitchID = ?');
     $sth->execute($dbshoe,$curr_game[4],$player);
     $sth->finish;
     my $winnings = 0;
     if (valuehand($curr_game[3]) > valuehand($curr_game[4]) || valuehand($curr_game[4]) > 21) {
          if (valuehand($curr_game[3]) == 21 && length($curr_game[3]) == 4) {
               $winnings = int($curr_game[5] * 2.5);
          } else {
               $winnings = $curr_game[5] * 2;
          }
          $gamemsg = show_game($player,1);
          if (valuehand($curr_game[4]) > 21) {
               $gamemsg = $gamemsg." Dealer Busted! ";
          }
          $gamemsg = $gamemsg.$player." Wins ".$winnings." tokens!";
     } elsif (valuehand($curr_game[3]) == valuehand($curr_game[4])) {
          $gamemsg = show_game($player,1)." ".$player." game is a Push.";
          $winnings = $curr_game[5];
     } else {
          $gamemsg = show_game($player,1)." ".$player." Lost!";
     }
     if ($winnings > 0) {
          token_add("evepriceinfo",$winnings,$player);
          $sth = $dbh->prepare('UPDATE TokenStats SET BJTokensOut = BJTokensOut + ? WHERE StatDate = current_date');
          $sth->execute($winnings);
          $sth->finish;
     }
     $sth = $dbh->prepare('UPDATE BJGame SET Hand = NULL, Dealer = NULL, Bet = NULL, TTL = NULL WHERE TwitchID = ?');
     $sth->execute($player);
     $sth->finish;
     return $gamemsg;
}

sub newshoe {
     my $player = $_[0];
     my $bet = $_[1];
     my $shoe = [ shuffle map { my $c=$_; map {"$c$_"} qw(H D C S) } ( 2 .. 9, qw( T J Q K A ) ) x 6];
     my $dbshoe = encodedeck(\@{$shoe});
     my $entry = $dbh->selectrow_array("SELECT TwitchID FROM BJGame WHERE TwitchID LIKE \"$player\"");
     if ($entry) {
          $sth = $dbh->prepare('UPDATE BJGame SET Shoe = ?, Bet = ?, Hand = NULL, Dealer = NULL, TTL = NULL WHERE TwitchID = ?');
          $sth->execute($dbshoe,$bet,$player);
     } else {
          $sth = $dbh->prepare('INSERT INTO BJGame (TwitchID,Shoe,Bet,TTL) VALUES (?,?,?,NULL)');
          $sth->execute($player,$dbshoe,$bet);
     }
     $sth->finish;
}

sub givecard {
     my $player = $_[0];
     my @shoe = ( $_[1] =~ m/../g );
     my $hand = $_[2];
     $hand = $hand.shift @shoe;
     my $dbshoe = "";
     foreach my $card (@shoe) {
          $dbshoe = $dbshoe.$card;
     }     
     $sth = $dbh->prepare('UPDATE BJGame SET Shoe = ?, Hand = ?, TTL = NULL WHERE TwitchID = ?');
     $sth->execute($dbshoe,$hand,$player);
     $sth->finish;
     return $hand;
}

sub deal {
     my $player = $_[0];
     my @shoe = ( $_[1] =~ m/../g );
     my $bet = $_[2];
     my $hand;
     my $dealer;
     $hand = shift @shoe;
     $dealer = shift @shoe;
     $hand = $hand.shift @shoe;
     $dealer = $dealer.shift @shoe;
     my $dbshoe = "";
     foreach my $card (@shoe) {
          $dbshoe = $dbshoe.$card;
     }     
     $sth = $dbh->prepare('UPDATE BJGame SET Shoe = ?, Hand = ?, Dealer = ?, Bet = ?, TTL = NULL WHERE TwitchID = ?');
     $sth->execute($dbshoe,$hand,$dealer,$bet,$player);
     $sth->finish;
}

sub get_curr_game {
     my $nick = $_[0];
     my $sth = $dbh->prepare('SELECT * FROM BJGame WHERE TwitchID = ?');
     $sth->execute($nick);
     my @curr_game = $sth->fetchrow_array;
     $sth->finish;
     return ($curr_game[0],$curr_game[1],$curr_game[2],$curr_game[3],$curr_game[4],$curr_game[5],$curr_game[6]);
}

1;