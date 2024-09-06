#!/usr/bin/perl

use strict;
use warnings;

use MIME::Lite;
use DBM::Deep;
use Carp;
use Getopt::Long;
use HTTP::Request::Common;
use JSON;
use LWP::UserAgent;

#
# Tool to query APRS.fi and send an email if the location has updated. This was
# designed for testing an rx-only igate that is also out of range of the nearest
# digi, so no easy way to tell with pure RF that the packet was gated. (Also an
# option: building a real igate... but Perl scripts are a lot cheaper.)
#

my $callsign;       # --callsign   : callsign with SSID
my $api_key;        # --api_key    : your aprs.fi api key
my $from_email;     # --from_email : from address for the email
my $to_email;       # --to_email   : to address for the email

GetOptions(
    "callsign=s"   => \$callsign,
    "api_key=s"    => \$api_key,
    "to_email=s"   => \$to_email,
    "from_email=s" => \$from_email,
) or die "Invalid arguments";

my $r = aprsfi_call('get', {
    name   => $callsign,
    what   => 'loc',
    apikey => $api_key,
    format => 'json',
});

my $dbm = DBM::Deep->new('/var/tmp/aprsfi-result');

die "APRS.fi API failure: $r->{description}"
    if $r->{result} eq 'fail';

my $seen = $dbm->{"seen_$callsign"} || {};
my $new;
for my $loc (@{ $r->{entries} || [] })
{
    next if $seen->{ $loc->{time} };
    $seen->{ $loc->{time} } = 1;
    $new = $loc;
}

$dbm->put("seen_$callsign" => $seen);

if ($new)
{
    my $email = MIME::Lite->new(
        From    => $from_email || 'no-reply@localhost',
        To      => $to_email,
        Subject => 'New APRS PATH',
        Data    => "Path: $new->{path}\nLat: $new->{lat} Long: $new->{lng}",
    );

    $email->send;
}

sub aprsfi_call
{
    my ($url, $params) = @_;

    $url = "https://api.aprs.fi/api/$url";
    $url .= "?";
    for my $param (keys %$params)
    {
        $url .= "$param=$params->{$param}&";
    }

    my $lwp = LWP::UserAgent->new;
    my $http_request = POST(
        $url,
        Content_Type => 'application/json',
        Accept       => 'application/json',
    );

    my $response = $lwp->request($http_request);

    croak "No response content"
        unless $response->decoded_content;

    my $decoded_content = $response->decoded_content;
       $decoded_content =~ s/[^[:print:]\r\n]//g;

    return JSON->new->decode($decoded_content);
}

