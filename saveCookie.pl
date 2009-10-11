#!/usr/bin/perl
# example for saving a cookie needed to retrieve NZBs
# copyleft Sven Knispel
# History
# 2009-10-10	v0.1	Initial version
# TODO

use LWP::UserAgent;
use HTTP::Cookies;
use YAML::Tiny;
use Log::Log4perl;

use strict;

my $config = YAML::Tiny->read('rss-processor.conf');

my $sourceDir	= $config->[0]->{'rss-path'};
my $targetDir	= $config->[0]->{'nzb-path'};
my $cacheDir	= $config->[0]->{'cache-path'};
my $cookieDir	= $config->[0]->{'cookie-path'};

# init logging
my $conf_file = 'rss-tools.logconfig';
Log::Log4perl->init( $conf_file );
my $logger = Log::Log4perl::get_logger('main');


die ("directory $cookieDir does not exist" && $logger->logdie("directory $cookieDir does not exist")) unless (-e $cookieDir);        

$cookieDir .= "/" unless ($cookieDir eq "");

# following vars must be set to proceed
my $cookieFile	= "revo.cookie";
my $userName 	= "chamonix";
my $password	= "lomfeen";
my $loginURI	= "http://www.usenetrevolution.info/vb/login.php?do=login";

my $cookie_jar = HTTP::Cookies->new(
  file => $cookieDir . $cookieFile,
  autosave => 1
);

my $browser = LWP::UserAgent->new;
$logger->info("Getting $loginURI with cookie '" . $cookieDir . $cookieFile . "'");
#      $browser->cookie_jar({ file => $cookieDir . $cookieFile });
$browser->cookie_jar($cookie_jar);

# post data for usenetrevolution.info
my %form = (
    'vb_login_username' 	=> $userName,
    'vb_login_password' 	=> $password,
    's'			=> '',
    'securitytoken'	=> 'guest',
    'do'			=> 'login',
    'vb_login_md5password'	=> '',
    'vb_login_md5password_utf'	=> '',
    'cookieuser'			=> 1);

my $response = $browser->post($loginURI, \%form);
if ($response->is_success)
{
  $logger->info($response->decoded_content);
}
else
{
  $logger->error($response->status_line);
}      


