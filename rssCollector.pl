#!/usr/bin/perl
# retrieve RSS feeds and save them as files
# copyleft Sven Knispel
# Last change:		$Date: 2009-10-11 15:49:29 +0200 (Sun, 11 Oct 2009) $
# By:			$Author: sven $
# Revision:		$Rev$
#
# History
# 2009-10-10	v0.1	Initial version
# 2009-10-10	v0.2	Added handling of option from config file
#			feeds are defined in config
#			log level is defined in config
#			target directory is defined in config
#			added proper logging (see definition in rss-tools.logconfig
# 2009-10-13	v0.3	Cleaned up logging for it to be screen-friendly
#			Added inline POC documentation
#			Added command line parameters
#			Added -v|--verbose option to show debug messages
# 2009-10-18	v0.4	Added proper error handling for RSS retrieval
# 2009-10-27	v0.5	Fix when LWP::Simple does not return correct data
#			Error handling on HTTP errors fixed
#
# TODO


use LWP::Simple;
use YAML::Tiny;
use Log::Log4perl qw(get_logger :levels);
use Pod::Usage;
use Getopt::Long ;

use strict;

my $help 	= 0 ;
my $man 	= 0 ;
my $verbose		= 0;
my $conf 	= "rss2nzb.conf";
my $logger_conf	= "rss-tools.logconfig";

GetOptions(
    "help|?"            => \$help,
    "man"               => \$man,
    "config-file|f=s"	=> \$conf,
    "verbose|v"		=> \$verbose
    );

my $testFeed = lc $ARGV[0];

pod2usage(status => 0, -verbose => 99, sections => 'NAME|SYNOPSIS|DESCRIPTION|VERSION') if $help ;
pod2usage(-exitstatus => 0, -verbose => 99, sections => 'NAME|SYNOPSIS|DESCRIPTION|VERSION|CONFIGURATION|EXAMPLE') if $man ;

# init logging
Log::Log4perl->init( $logger_conf );
my $logger = Log::Log4perl::get_logger('main');
if ($verbose == 1)
{
  $logger->level($DEBUG);
  Log::Log4perl->appender_thresholds_adjust(-1, ['Screen']);
}

my $config = YAML::Tiny->read($conf) ||
   $logger->logdie("Configuration file $conf is missing");

my $node 	= $config->[0]->{'feeds'};
my %feeds 	= %{$node};
my $targetDir	= $config->[0]->{'rss-path'};

# init logging
my $conf_file = 'rss-tools.logconfig';
Log::Log4perl->init( $conf_file );
my $logger = Log::Log4perl::get_logger('main');

$logger->logdie("directory $targetDir does not exist") unless (-e $targetDir);

$targetDir .= "/" unless ($targetDir eq "");

foreach my $key (keys %feeds)
{
  if (($testFeed ne "") && ($feeds{$key}{'rss-file'} ne $testFeed))
  {
    $logger->debug("Collecting restricted to $testFeed, skipping $feeds{$key}{'rss-file'}");
    next;
   };

  # check if download has to ouccur
  # date of file is 0 if file does not exist, else the date of last change
  my $fileDate = 0;
  my $now = time;
  $logger->info("Checking " . $feeds{$key}{'rss-file'});
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
    $logger->info("Retrieving $key from ". $feeds{$key}{'url'});
    my $response = LWP::Simple::getstore($feeds{$key}{'url'}, $targetDir . $feeds{$key}{'rss-file'});
    if (!(LWP::Simple->is_success($response)))
    {
      $logger->error("The RSS feed '" . $feeds{$key}{'url'} . "' cound not be retrieved. Response was '$response'");
    }
  }
  else
  {
    $logger->debug("Skipping: $key, file is less than $feeds{$key}{'poll'} minutes old ($fileAge)");
  }
}

__END__

=head1 NAME

rssCollector.pl - An rss feed grabber

=head1 SYNOPSIS

perl rssCollector.pl [-f <config-file>|--config-file=<config-file>] [<feed-file>]

 Options:
   -f, --config-file    use specific config file
   -v, --verbose        show more info about what happens
   -?, --help		shows this help
   --man		shows the full help
   feed-file		restrict the processing to a single feed by naming the file

=head1 OPTIONS

=over 4

=item B<--help>
Print a brief help message and exits.

=item B<--man>
Prints the manual page and exits.

=back

=head1 DESCRIPTION

This program will read the rss-processor.conf file and download rss feeds defined there to files.

=head1 CONFIGURATION

The configuration is done in YAML syntax in a common fashion for all rss2nzb utilities.

=over

=item feeds:
is the iterator for all the feeds to be processed by the rss2nzb utilities.

=item nzb-path:
is the directory where nzb files will be stored (overridable at feed level)

=item rss-path:
is the directory where rss-feed files will be stored

=item cache-path:
is the directory where the nzb cache will be kept

=item cookie-path:
is the directory where the rss2nzb utilities will look for cookies

=item notify-method:
the method notifications should be send with (rss|mail)

=item notify-to:
the destination notifications shall be written to. For 'rss' it is a rss file with path, for mail it is an address

=back

The definition of feeds looks like:

=over

=item feeds:

=over

=item <name>:
The name of the feed

=over

=item 'rss-file:'
The name of the file the rss feed will be save to

=item 'url:'
The URL for retrieving the rss feed

=item 'matches:'
A comma separated list of regex to match the title of rss items (whitelist)

=item 'rejects:'
A comma separated list of regex not to match the title of rss items (blacklist)

=item 'poll:'
The frequency to poll the feed (in minutes)

=item 'action:'
Optional: the action to take with <link> of the rss <item>. Valid values are nzb|guessnzb|dump

=item 'link-tag:'
Optional: the tag where to find the link. Default is <link> but it can be overridden. Valid values are any tag from the feed

=item 'auth:'
Optional: an authentication string to be appended to URL when retrieving NZBs (session ID for site requiring auth)

=item 'regexp:'
Optional: it can be required to define a regexp to determine the URL of the link for download. In that case the regexp must contain a part between () to be used as match

=item 'nzb-path:'
Optional: path for saving NZBs. If defined at feed level this definition overrides the global nzb-path

=back

=back

=back

=head1 EXAMPLE

Following example is a minimum definition of one feed to be processed by rss2nzb utilities.

=begin text

          feeds:
            myfeedname:
              matches: ^House,^Ŵeeds
              rejects: 720p
              rss-file: series.xml
              url: http://my-favorite-rss/rss.xml
            nzb-path: /home/me/rss2nzb
            rss-path: /home/me/rss2nzb/rss
            cache-path: /home/me/rss2nzb/cache
            cookie-path: /home/me/rss2nzb/cookies

=end text

=cut

