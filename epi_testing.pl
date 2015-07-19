#!/bin/perl

use strict;
use warnings;
use LWP::Simple qw(!head);
use JSON;
use Data::Dumper;

my $url = "http://tmi.twitch.tv/group/user/rushlock/chatters";     
my $result = decode_json(get($url));
print $result->{'chatter_count'}."\n";
foreach my $nick (@{$result->{'chatters'}{'viewers'}}) {
   print $nick."\n";
}
#print Dumper $result->{'chatters'}{'viewers'};
#print Dumper $result->{'chatters'}{'moderators'};
