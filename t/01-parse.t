use 5.24.0;
use strict;
use warnings;
use utf8;
use Test::More;
use File::Spec;
use JSON::PP qw(decode_json);

use FindBin;
use lib "$FindBin::Bin/../lib";
use Weather::METNO;

my $fixture = File::Spec->catfile($FindBin::Bin, 'data', 'complete.json');
open my $fh, '<:raw', $fixture or die $!;
my $data = decode_json(do { local $/; <$fh> });

my $t0    = Weather::METNO::_iso_to_epoch('2026-09-15T20:00:00Z');
my $t6h   = Weather::METNO::_iso_to_epoch('2026-09-18T12:00:00Z');
my $w     = Weather::METNO->from_hash($data, lang => 'en', now => $t0);

is $w->temp_c, 20.5, 'temp_c';
is $w->temp_f, 68.9, 'temp_f';
is $w->temp_apparent_c, 19.8, 'apparent temp';
is $w->humidity, 55.5, 'humidity';
is $w->cloudiness, 42.0, 'cloudiness';
is $w->clouds_low, 20.0, 'low clouds';
is $w->symbol, 'fair_night', 'symbol from next_1_hours';
is $w->symbol_txt, 'Fair', 'legend text';
is $w->precip, 0.2, 'precip 1h';
is $w->precip_prob, 40.0, 'precip probability';
is $w->thunder_prob, 2.0, 'thunder probability';
is $w->temp_min_c, 16.4, 'min next 6h';
is $w->temp_max_c, 21.0, 'max next 6h';
is $w->windfrom_dir, 'N', '0 deg is N';
is $w->windspeed_kmh, 12.2, 'm/s to km/h';
is $w->updated_at, Weather::METNO::_iso_to_epoch('2026-09-15T19:26:01Z'), 'updated_at epoch';
like $w->as_string, qr/20\.5°C/, 'as_string';
like $w->symbol_url, qr/fair_night\.png$/, 'icon url';

my $later = $w->in(hours => 64);
is $later->forecast_time, $t6h, 'in(hours => 64) lands on second step';
is $later->symbol, 'cloudy', 'falls back to next_6_hours symbol';
is $later->precip, 1.5, 'falls back to next_6_hours precip';
is $later->temp_c, 17.2, 'later temp';
is $later->windfrom_dir, 'N', '359.9 deg wraps to N';

my $last = $w->at(9_999_999_999);
is $last->temp_c, 12.0, 'past the series uses last point';
is $last->symbol, undef, 'instant-only point has no symbol';
is $last->precip, undef, 'instant-only point has no precip';
is $last->windfrom_dir, 'E', '90 deg is E';

my @steps = $w->steps;
is scalar @steps, 3, 'three steps';
is $steps[0]->temp_c, 20.5, 'step 0';
is $steps[2]->temp_c, 12.0, 'step 2';

# Two objects must not share mutable state.
my $a = Weather::METNO->from_hash($data, now => 1);
my $b = $a->at(9_999_999_999);
is $a->temp_c, 20.5, 'original object unchanged after at()';
is $b->temp_c, 12.0, 'clone is independent';

done_testing;
