#!/usr/bin/perl
# retrieve NZB files from RSS feeds based on regex rules and reject rules
# copyleft Sven Knispel
# Last change:		$Date$
# By:			$Author$
# Revision:		$Revision$
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
#
# TODO

use XML::RSS;
use LWP::Simple;
use LWP::UserAgent;
use YAML::Tiny;
use Log::Log4perl;
use File::Touch;

use strict;

my $config = YAML::Tiny->read('rss-processor.conf');

my $node 	= $config->[0]->{'feeds'};
my %feeds 	= %{$node};

my $sourceDir	= $config->[0]->{'rss-path'};
my $targetDir	= $config->[0]->{'nzb-path'};
my $cacheDir	= $config->[0]->{'cache-path'};
my $cookieDir	= $config->[0]->{'cookie-path'};

# init logging
my $conf_file 	= 'rss-tools.logconfig';

Log::Log4perl->init($conf_file);
my $logger 	= Log::Log4perl::get_logger('main');


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
  my $sourceFile	= $feeds{$feed}{'rss-file'};
  my $rss 		= XML::RSS->new;

  if (!(-e $sourceDir . $sourceFile))
  {
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

	  # default action is 'getnzb' but it can be overridden by setting feed property 'action' to 'dump' or 'guessnzb' 
	  my $linkAction 	= $feeds{$feed}{'action'};
	  $linkAction 	= "getnzb" 	unless ($linkAction ne "");

	  # default behaviour is not to use cookies but it can be overridden by setting feed property 'use-cookie' to a LWP cookie file 
	  my $cookieFile 	= $feeds{$feed}{'use-cookie'};

	  $logger->debug("Going to retrieve tag: '$linkTag' with action '$linkAction'");
	  
	  # go for normal action: download the link as nzb
	  if ($linkAction eq "getnzb")
	  {
	    getNzb($item->{'title'}, $item->{$linkTag});
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
	    $logger->debug("Trying to guess NZB URL with regexp '$regexp'");
	    $_ = $value;
	    my $regexp = $feeds{$feed}{'regexp'};

	    if (/$regexp/)
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
	    getNzb($item->{'title'}, $link, $cookieFile);
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

      my $browser = LWP::UserAgent->new;
      $logger->info("Getting $URI with cookie '" . $cookieDir . $cookieFile . "'");
      if ($cookieFile ne "")
      {
	$browser->cookie_jar({ file => $cookieDir . $cookieFile });
      }
      else
      {
	$browser->cookie_jar({ });
      }

      $browser->get($URI, ':content_file' => $targetDir . $fileName);

      File::Touch::touch($cacheDir . $fileName);
    }
    else
    {
      $logger->info("Skipping: file $fileName already exists in cache");
    }
  }
  else
  {
    $logger->info("Skipping: file $fileName already exists");
  }
}

# removes illegal chars from title for saving it as file
sub normalizeTitle
{
  my ($title) = @_;

  $title =~s/\//_/g;	# / would be a directory, replace by _
  $title =~s/~/_/g;	# ~ would be a my home, replace by _ 
  $title = $_;

  my $fileName = $title . '.nzb';
  $logger->debug("Normalized '$title' into '$fileName");

  return $fileName;
}

