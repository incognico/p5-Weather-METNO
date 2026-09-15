#!/usr/bin/env perl
use 5.24.0;
use utf8;
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Weather::METNO;

binmode STDOUT, ':encoding(UTF-8)';

my ($lat, $lon, $uid) = @ARGV;
$uid ||= $ENV{METNO_UID} || die "usage: $0 LAT LON EMAIL_OR_DOMAIN\n";
$lat ||= 52.52;
$lon ||= 13.41;

my $w = Weather::METNO->new(lat => $lat, lon => $lon, uid => $uid, lang => 'en');

say $w->as_string;
say sprintf 'feels like %.1f°C  precip %.1f mm (%s%%)  thunder %s%%',
   $w->temp_apparent_c // $w->temp_c,
   $w->precip // 0,
   $w->precip_prob // 'n/a',
   $w->thunder_prob // 'n/a';

say '';
say 'next 12h:';
for my $s (grep {
      $_->forecast_time >= $w->forecast_time
      && $_->forecast_time <= $w->forecast_time + 12 * 3600
   } $w->steps)
{
   my @t = gmtime $s->forecast_time;
   say sprintf '  %02d:%02d  %5.1f°C  %-18s  %s %.1f mm',
      $t[2], $t[1],
      $s->temp_c,
      $s->symbol_txt // '—',
      $s->windfrom_dir_utf8arrow // '',
      $s->precip // 0;
}
