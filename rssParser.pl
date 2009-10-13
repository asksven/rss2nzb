#!/usr/bin/perl
# retrieve NZB files from RSS feeds based on regex rules and reject rules
# copyleft Sven Knispel
# Last change:		$Date: 2009-10-11 15:50:17 +0200 (Sun, 11 Oct 2009) $
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
# 2009-10-11	v0.3	Added handling of alternative RSS feed:
#			Feeds like usenet revolutions do not store NZB in 'link' but in 'content:encoded'
#				optional fields have been added to feeds to support that:
#					'link-tag' names the tag to be used for NZB file, default is 'link'
#					'action' can be default or "guessnzb|dump" when the URL is to be found in a CDATA (guess is with regexp from field 'regexp')
#			For pages requiring authentification optional field 'use-cookie' was added. That field should contain a valid LWP cookie
#				I create a utility saveCookie.pl as example on how to retrieve a cookie as wget cookies can not be used with LWP
# 2009-10-13	v0.4	Cleaned up logging for it to be screen-friendly
#			Added inline POD documentation
#			Added command line parameters
#			Added 'auth' parameter for feeds requiring a session ID
#
# TODO

use XML::RSS;
use LWP::Simple;
use LWP::UserAgent;
use HTTP::Request;
use YAML::Tiny;
use Log::Log4perl;
use File::Touch;
use Pod::Usage;
use Getopt::Long ;

use strict;

my $help 	= 0 ;
my $man 	= 0 ;
my $conf 	= "rss2nzb.conf";
my $conf_file 	= 'rss-tools.logconfig';



GetOptions(
    "help|?"            => \$help,
    "man"               => \$man,
    "config-file|f=s"	=> \$conf
    );

my $testFeed = lc $ARGV[0];

pod2usage(status => 0, -verbose => 99, sections => 'NAME|SYNOPSIS|DESCRIPTION|VERSION') if $help ;
pod2usage(-exitstatus => 0, -verbose => 99, sections => 'NAME|SYNOPSIS|DESCRIPTION|VERSION|CONFIGURATION|EXAMPLE') if $man ;

# init logging
Log::Log4perl->init($conf_file);
my $logger 	= Log::Log4perl::get_logger('main');

my $config = YAML::Tiny->read($conf)
    || $logger->logdie("Config file $conf is missing");

my $node 	= $config->[0]->{'feeds'};
my %feeds 	= %{$node};

my $sourceDir	= $config->[0]->{'rss-path'};
my $targetDir	= $config->[0]->{'nzb-path'};
my $cacheDir	= $config->[0]->{'cache-path'};
my $cookieDir	= $config->[0]->{'cookie-path'};




die ("directory $sourceDir does not exist"	&& $logger->logdie("directory $sourceDir does not exist"))	unless (-e $sourceDir);
die ("directory $targetDir does not exist" 	&& $logger->logdie("directory $targetDir does not exist")) 	unless (-e $targetDir);
die ("directory $cacheDir does not exist" 	&& $logger->logdie("directory $cacheDir does not exist")) 	unless (-e $cacheDir);
die ("directory $cookieDir does not exist" 	&& $logger->logdie("directory $cookieDir does not exist")) 	unless (-e $cookieDir);        

$sourceDir	.= "/" unless ($sourceDir eq "");
$targetDir 	.= "/" unless ($targetDir eq "");
$cacheDir 	.= "/" unless ($cacheDir eq "");
$cookieDir 	.= "/" unless ($cookieDir eq "");


foreach my $feed (keys %feeds)
{
  if (($testFeed ne "") && ($feeds{$feed}{'rss-file'} ne $testFeed))
  {
    $logger->debug("Processing restricted to $testFeed, skipping $feeds{$feed}{'rss-file'}");
    next;
  };

  my $sourceFile	= $feeds{$feed}{'rss-file'};
  my $rss 		= XML::RSS->new;

  if (!(-e $sourceDir . $sourceFile))
  {
    $logger->warn("$sourceFile was not found in $sourceDir");
    next;
  }

  $rss->parsefile($sourceDir . $sourceFile) ;

  # print the title and link of each RSS item
  foreach my $item (@{$rss->{'items'}})
  {
    my @filters = split(/,/, $feeds{$feed}{'matches'});
    foreach my $filter (@filters)
    {
      $logger->debug("trying to match '$filter' on '" . $item->{'title'});
      if ($item->{'title'} ~~ m/$filter/)
      {
	$logger->debug("match");
	my @rejects	= split(/,/, $feeds{$feed}{'rejects'});
	my $rejected 	= 0;
	foreach my $reject (@rejects)
	{
	  $logger->debug("trying to reject rule '$reject' on '" . $item->{'title'});
	  if ( ($rejected == 0) && ($item->{'title'} ~~ m/$reject/))
	  {
	    $rejected = 1;
	    $logger->debug("reject rule applies");
	  }
	}
	if ($rejected == 0)
	{
	  $logger->debug("Match found: $item->{'title'}");
	  # default link tag is "link" but it can be overridden by setting feed property 'link-tag' in case the rss does not point to NZBs
	  my $linkTag		= $feeds{$feed}{'link-tag'};
	  $linkTag 	= "link"	unless ($linkTag ne "");
	  my $auth	= $feeds{$feed}{'auth'};
	  $auth		= ('&' . $auth) unless ($auth eq "");

	  # default action is 'getnzb' but it can be overridden by setting feed property 'action' to 'dump' or 'guessnzb' 
	  my $linkAction 	= $feeds{$feed}{'action'};
	  $linkAction 	= "getnzb" 	unless ($linkAction ne "");

	  # default behaviour is not to use cookies but it can be overridden by setting feed property 'use-cookie' to a LWP cookie file 
	  my $cookieFile 	= $feeds{$feed}{'use-cookie'};

	  $logger->debug("Going to retrieve tag: '$linkTag' with action '$linkAction'");
	  
	  # go for normal action: download the link as nzb
	  if ($linkAction eq "getnzb")
	  {
	    getNzb($item->{'title'}, $item->{$linkTag} . $auth);
	  }
	  # alternative action 'dump' is for debugging purpose
	  elsif ($linkAction eq "dump")
	  {
	    my $value 	= "";
	    my $link 	= "";
	    
	    # content encoded is a special case as 'content' is a hashmap
	    if ($linkTag eq "content:encoded")
	    {
	      $value = $item->{'content'}->{'encoded'};
	    }
	    else
	    {
	      $value = $item->{$linkTag};
	    }

	    $logger->debug("DUMP:::" . $value . ":::");	    
	  }

	  # method to extract nzb URL from a field using regex from feed attribue 'regexp'
	  elsif ($linkAction eq "guessnzb")
	  {
	    my $value 	= "";
	    my $link 	= "";
	    
	    # content encoded is a special case as 'content' is a hashmap
	    if ($linkTag eq "content:encoded")
	    {
	      $value = $item->{'content'}->{'encoded'};
	    }
	    else
	    {
	      $value = $item->{$linkTag};
	    }
	    
	    # extract nzb by regexp
	    # e.g. for regexp for usenet revo: .*\<a href=\"(.*attachment.*)\"\>.* matches the URL
	    my $regexp = $feeds{$feed}{'regexp'};
	    $logger->debug("Trying to guess NZB URL with regexp '$regexp'");

	    if ($value =~ /$regexp/)
	    {
	      $logger->debug("Matched link $1");
	      $link = $1;
	      # normalize encoded parts
	      $link =~ s/&amp;/&/g;
	    }
	    else
	    {
	      $logger->debug("No match found");
	    }
	    
	    # if a link was found assume it's an NZB and download it
	    getNzb($item->{'title'}, $link . $auth, $cookieFile);
	  }
	  else
	  {
	    $logger->error("Undefined action '$linkAction' for feed $feed. No action taken");
	  }
	}
      }
      else
      {
	$logger->debug("no match");
      }
    }
  }
}


# retrieve linked file
sub getNzb
{
  my ($title, $URI, $cookieFile) = @_;
 
  my $fileName = &normalizeTitle($title);
  # donload only if file does not already exist
  if (!( -e ($targetDir . $fileName) ))
  {
    # check if in cache
    if (!( -e ($cacheDir . $fileName) ))
    {
      $logger->info("Downloading $title from $URI");
      
      $logger->debug("Cookie found, using LWP::UserAgent");
      my $browser = LWP::UserAgent->new;
      $logger->debug("Getting $URI with cookie '" . $cookieDir . $cookieFile . "'");
      if ($cookieFile ne "")
      {
	$browser->cookie_jar({ file => $cookieDir . $cookieFile });
      }
      my $req= HTTP::Request->new('GET',$URI);

      # set header as certain webservers were found to be picky and returning error 601
      $req->header('Accept' => '*/*');
      $req->header('User-Agent' => 'Wget/1.11.4');

      $logger->debug("request accept:" . $req->header('Accept'));

      my $response = $browser->request($req, $targetDir . $fileName);

      if ($response->is_success)
      {
	$logger->debug("Downloaded: $response->decoded_content");
	File::Touch::touch($cacheDir . $fileName);
      }
      else
      {
	$logger->error("Error " . $response->status_line);
      }
    }
    else
    {
      $logger->debug("Skipping: file $fileName already exists in cache");
    }
  }
  else
  {
    $logger->debug("Skipping: file $fileName already exists");
  }
}

# removes illegal chars from title for saving it as file
sub normalizeTitle
{
  my ($title) = @_;

  $title =~s/\//_/g;	# / would be a directory, replace by _
  $title =~s/~/_/g;	# ~ would be a my home, replace by _ 

  my $fileName = $title . '.nzb';
  $logger->debug("Normalized '$title' into '$fileName");

  return $fileName;
}

__END__

=head1 NAME

rssCollector.pl - An rss feed grabber

=head1 SYNOPSIS

perl rssParser.pl [-f <config-file>|--config-file=<config-file>] [<feed-file>]

 Options:
   -f, --config-file    use specific config file
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

The configuration is done in YAML syntax in a common fashion for all rss2nzb utilities. For help see perl rssConfig.pl --man


=cut
