#!/usr/bin/perl
# create a config file for rss*
# copyleft Sven Knispel
# History
# 2009-10-10	v0.1	Initial version
#
# TODO

use YAML::Tiny;
use strict;

my $config = YAML::Tiny->new;

# write am example config file
# path
$config->[0]->{'nzb-path'} = 'nzb';
$config->[0]->{'rss-path'} = 'rss';

# general settings
$config->[0]->{'nzb-cache'} = 0;
$config->[0]->{'log-level'} = 1;

# feeds
my %feeds = ();
$feeds{'NZBSerien'} 		= {
    'rss-file'	=> 'serien.xml',
    'url' 	=> "http://nzbserien.org/serien.xml",
    'poll' 	=> 15,
    'matches'	=> "GERMAN,^NCIS",
    'rejects'	=> "720"
  };
$feeds{'NZBs.org TV XVid'}	= {
    'rss-file'	=> 'nzbs_tv_xvid.xml',
    'url'	=> 'http://www.nzbs.org/rss.php?catid=1&h=4ab98ec7f7058298391c767604a4c173&dl=1',
    'poll'	=> 60,
    'matches'	=> "GERMAN,^NCIS",
    'rejects'	=> "720"
  };

$config->[0]->{'feeds'} = \%feeds;

$config->write('rss-processor.conf');

# read a config file
$config = YAML::Tiny->read('rss-processor.conf');
my $feeds2 = $config->[0]->{'feeds'};
my %res = %{$feeds2};

foreach my $key (keys %res)
{
  print "Feed $key\n";
  print "\t$key $res{'url'}\n";
  
}