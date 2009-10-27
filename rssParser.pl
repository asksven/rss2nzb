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
#			Added option to override default target dir at a feed basis
#			Added notification of whatever the process resulted in (rss and mail are supported)
#			Added global error handling for showing stacktrace in case of unexpected errors
#			Added -v|--verbose option to show debug messages
# 2009-10-18	v0.5    Added error handling for call to XML::RSS->parse
#			Added try-catch block for parsing to avoid die on XML error
#
# TODO
#			Add -s(imulation) mode for the parser to show what it would do
#			Externalize the notifier in a helper class
#

use XML::RSS;
use LWP::Simple;
use LWP::UserAgent;
use HTTP::Request;
use YAML::Tiny;
use Log::Log4perl qw(get_logger :levels);
use File::Touch;
use Pod::Usage;
use Getopt::Long;
use Devel::StackTrace;

use ex::override GLOBAL_die => sub
{
    local *__ANON__ = "custom_die";
    print
        'Error: ', @_, "\n",
        "Stack trace:\n",
        Devel::StackTrace->new(no_refs => 1)->as_string, "\n";
    exit 1;
};


use strict;

my $help 		= 0 ;
my $man 		= 0 ;
my $verbose		= 0;
my $conf 		= "rss2nzb.conf";
my $conf_file 		= 'rss-tools.logconfig';
my @notifications	= ();


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
Log::Log4perl->init($conf_file);
my $logger 	= Log::Log4perl::get_logger('main');
if ($verbose == 1)
{
  $logger->level($DEBUG);
  Log::Log4perl->appender_thresholds_adjust(-1, ['Screen']);
}

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
  eval
  {
    $rss->parsefile($sourceDir . $sourceFile) ;
  };
  if ($@)
  {
    $logger->info("An error occured during parsing of '$sourceFile'. Error was '$@'");
    next;
  };

  # print the title and link of each RSS item
  foreach my $item (@{$rss->{'items'}})
  {
    # path for storing nzbs is either the global path or was overridden at feed level
    my $nzbPath = $targetDir;
    $nzbPath = ($feeds{$feed}{'nzb-path'} . "/") unless ($feeds{$feed}{'nzb-path'} eq "");

    my @filters = split(/,/, $feeds{$feed}{'matches'});
    $logger->debug("trying matches '" . $feeds{$feed}{'matches'} . "' on " . $item->{'title'});
    foreach my $filter (@filters)
    {
      if ($item->{'title'} ~~ m/$filter/)
      {
	$logger->debug("match");
	my @rejects	= split(/,/, $feeds{$feed}{'rejects'});
	my $rejected 	= 0;
        $logger->debug("trying rejects expressions '" . $feeds{$feed}{'rejects'} . "' against " . $item->{'title'});
	foreach my $reject (@rejects)
	{
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
	  my $linkTag	= $feeds{$feed}{'link-tag'};
	  $linkTag 	= "link"	unless ($linkTag ne "");
	  my $auth	= $feeds{$feed}{'auth'};
	  $auth		= ('&' . $auth) unless ($auth eq "");

	  # default action is 'getnzb' but it can be overridden by setting feed property 'action' to 'dump' or 'guessnzb' 
	  my $linkAction 	= $feeds{$feed}{'action'};
	  $linkAction 	= "getnzb" 	unless ($linkAction ne "");

	  # default behaviour is not to use cookies but it can be overridden by setting feed property 'use-cookie' to a LWP cookie file 
	  my $cookieFile 	= $feeds{$feed}{'use-cookie'};

	  $logger->debug("Going to retrieve tag: '$linkTag' with action '$linkAction'");
	  #
	  # go for normal action: download the link as nzb
	  #
	  if ($linkAction eq "getnzb")
	  {
	    getNzb($item->{'title'}, $item->{$linkTag} . $auth, "", $nzbPath);
	  }
	  #
	  # alternative action 'dump' is for debugging purpose
	  #
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
	  #
	  # method to extract nzb URL from a field using regex from feed attribue 'regexp'
	  #
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
	    getNzb($item->{'title'}, $link . $auth, $cookieFile, $nzbPath);
	  }
	  else
	  {
	    $logger->error("Undefined action '$linkAction' for feed $feed. No action taken");
	  }
	}
      }
    }
  }
}

# write any notifications to the proper place
&postProcess;

# END


# retrieve linked file
sub getNzb
{
  my ($title, $URI, $cookieFile, $targetDir) = @_;
 
  my $fileName = &normalizeTitle($title);
  # donload only if file does not already exist
  if (!( -e ($targetDir . $fileName) ))
  {
    # check if in cache
    if (!( -e ($cacheDir . $fileName) ))
    {
      $logger->info("Downloading $title from $URI to " . $targetDir . $fileName);
      
      my $browser = LWP::UserAgent->new;

      if ($cookieFile ne "")
      {
	$browser->cookie_jar({ file => $cookieDir . $cookieFile });
	$logger->debug("Getting $URI with cookie '" . $cookieDir . $cookieFile . "'");
      }
      else
      {
	$logger->debug("Getting $URI without cookie");
      }
      my $req= HTTP::Request->new('GET',$URI);

      # set header as certain webservers were found to be picky and returning error 601
      $req->header('Accept' => '*/*');
#      $req->header('User-Agent' => 'Wget/1.11.4');
      $req->header('User-Agent' => 'Mozilla/4.0 (compatible; MSIE 7.0b; Windows NT 6.0)');

      my $response = $browser->request($req, $targetDir . $fileName);

      if ($response->is_success)
      {
	$logger->debug("Downloaded: $response->decoded_content");
	File::Touch::touch($cacheDir . $fileName);
	&notify("Downloaded $title to " . $targetDir);
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

# store a notification
sub notify
{
  my ($message) = @_;
  push(@notifications, $message);
}

# send collected notifications
sub postProcess
{
  $logger->debug("Post-processing started");

  my $method  = $config->[0]->{'notify-method'};
  my $address = $config->[0]->{'notify-to'};

  return unless ($method ne "");

  if ($method eq "rss")
  {
    my $rss;

    # if the file does not exist create it
    # else read the existing one
    if (!( -e ($address)))
    {
      $logger->debug("creating rss file $address");
      $rss = XML::RSS->new (version => '2.0', stylesheet => 'http://ws-sven/rssstyle.xsl');
      $rss->channel(title          => 'rss2nzb',
               link           => '',
               language       => 'en',
               description    => 'Detected NZBs',
               copyright      => 'Copyright 2009',
               docs           => 'http://',
               );
    }
    else
    {
      $rss = XML::RSS->new;
      $rss->parsefile("$address");
    }

    # add whatever events occured during processing
    foreach my $message (@notifications)
    {
      $logger->debug("adding to rss feed: $message");
      my $dt = DateTime->now;
      $rss->add_item(title => $dt->dmy("/") . " " . $dt->hms(":") . " " . $message, link => "file://");
    }
    
    $logger->debug("saving rss to $address");
    $rss->save($address);
  }
  elsif ($method eq "mail")
  {
    my $message = "";
    foreach my $line (@notifications)
    {
      $message .= $line . "\n";
    }
    
    basicSendMail("rss2nzb", $address, "Notification from rss2nzb", $message);
  }
  else
  {
    $logger->error("Unsupported notification method: $method");
  }
}

sub basicSendMail {
    my ($from, $to, $subject, $message) = @_;

    my $mail = '' ;
    $mail .= "To: $to\n" ;
    $mail .= "Subject: $subject\n" ;
    $mail .= $message ;

    open SENDMAIL, "|/usr/lib/sendmail -t" or return -1 ;
    print SENDMAIL $mail ;
    close SENDMAIL ;
    return 1 ;
}

__END__

=head1 NAME

rssCollector.pl - An rss feed grabber

=head1 SYNOPSIS

perl rssParser.pl [-f <config-file>|--config-file=<config-file>] [<feed-file>]

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

=item B<--config-file>
Loads a given config-file instead of rss2nzb.conf

=item B<--verbose>
Prints debugging info

=back

=head1 DESCRIPTION

This program will read the rss-processor.conf file and download rss feeds defined there to files.

=head1 CONFIGURATION

The configuration is done in YAML syntax in a common fashion for all rss2nzb utilities. For help see perl rssConfig.pl --man


=cut
