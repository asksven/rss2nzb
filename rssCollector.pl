#!/usr/bin/perl
# retrieve RSS feeds and save them as files
# copyleft Sven Knispel
# History
# 2009-10-10	v0.1	Initial version
# 2009-10-10	v0.2	Added handling of option from config file
#			feeds are defined in config
#			log level is defined in config
#			target directory is defined in config
#			added proper logging (see definition in rss-tools.logconfig
#
# TODO


use LWP::Simple;
use YAML::Tiny;
use Log::Log4perl;

use strict;

my $config = YAML::Tiny->read('rss-processor.conf');

my $node 	= $config->[0]->{'feeds'};
my %feeds 	= %{$node};
my $targetDir	= $config->[0]->{'rss-path'};

# init logging
my $conf_file = 'rss-tools.logconfig';
Log::Log4perl->init( $conf_file );
my $logger = Log::Log4perl::get_logger('main');

die ("directory $targetDir does not exist" && $logger->logdie("directory $targetDir does not exist")) unless (-e $targetDir);

$targetDir .= "/" unless ($targetDir eq "");

foreach my $key (keys %feeds)
{
  # check if download has to ouccur
  # date of file is 0 if file does not exist, else the date of last change
  my $fileDate = 0;
  my $now = time;

  $logger->debug("Checking last modification date of file " . $feeds{$key}{'rss-file'});
  if (( -e $targetDir . $feeds{$key}{'rss-file'} ))
  {
    $fileDate = (stat($targetDir . $feeds{"$key"}{'rss-file'}))[9];
  }
  else
  {
    $logger->debug("File does not exist yet ". $feeds{"$key"}{'url'});
  }

  my $fileAge = ($now - $fileDate) / 60;
  $logger->debug("File ". $targetDir . $feeds{"$key"}{'rss-file'} . " was changed $fileAge minutes ago");

  if ( ($fileAge) > $feeds{$key}{'poll'} )
  {
    $logger->debug("Retrieving $key from ". $feeds{$key}{'url'});
    LWP::Simple::getstore($feeds{$key}{'url'}, $targetDir . $feeds{$key}{'rss-file'});
  }
  else
  {
    $logger->info("Skipping: $key, file is less than $feeds{$key}{'poll'} minutes old ($fileAge)");
  }
}
