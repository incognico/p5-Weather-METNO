package Weather::METNO;

use 5.24.0;
use utf8;
use strict;
use warnings;

use feature 'signatures';
no warnings 'experimental::signatures';

use Carp;
use File::Spec;
use HTTP::Date qw(str2time);
use HTTP::Message;
use JSON::PP qw(decode_json encode_json);
use LWP::UserAgent;
use Time::Local qw(timegm);

our $VERSION = '1.000';

my $API_URL = 'https://api.met.no/weatherapi/locationforecast/2.0/complete';
my $ICON_URL = 'https://distfiles.lifeisabug.com/metno';

sub new ($class, %args)
{
   my $self = $class->_init(%args);

   $self->{uid} // croak 'A unique identifier in the UA is required per TOS, best to set it to your domain/email.';
   defined $self->{lat} or croak 'lat not specified';
   defined $self->{lon} or croak 'lon not specified';

   $self->{lat} = 0 + sprintf('%.4f', $self->{lat});
   $self->{lon} = 0 + sprintf('%.4f', $self->{lon});
   $self->{alt} = int $self->{alt} if defined $self->{alt};

   $self->fetch_weather;
   return $self;
}

# Build an object from already-decoded JSON (tests, custom fetchers).
sub from_hash ($class, $data, %args)
{
   my $self = $class->_init(%args);
   $self->_load_symbols;
   $self->_ingest($data);
   return $self;
}

sub _init ($class, %args)
{
   return bless {
      uid       => $args{uid},
      lat       => $args{lat},
      lon       => $args{lon},
      alt       => $args{alt},
      lang      => $args{lang} // 'en',
      timeout   => $args{timeout} // 5,
      cache_dir => $args{cache_dir} // $ENV{METNO_CACHE} // File::Spec->tmpdir,
      now       => $args{now},
      symbols   => {},
      weather   => {},
      times     => [],
   }, $class;
}

sub fetch_weather ($self)
{
   $self->_load_symbols;

   my $ua    = $self->_ua;
   my $url   = $self->_url;
   my $cache = $self->_cache_file;
   my $cached;

   if (-f $cache)
   {
      $cached = eval { decode_json(_slurp($cache)) };
      if ($cached && ($cached->{_cache}{expires} // 0) > $self->_now)
      {
         $self->_ingest($cached);
         return;
      }
      $ua->default_header('If-Modified-Since' => $cached->{_cache}{last_modified})
         if $cached && $cached->{_cache}{last_modified};
   }

   my $r = $ua->get($url);

   if ($r->code == 304 && $cached)
   {
      $cached->{_cache} = $self->_cache_meta($r, $cached->{_cache});
      _spew($cache, encode_json($cached));
      $self->_ingest($cached);
      return;
   }

   croak $r->status_line unless $r->is_success;

   my $data = decode_json($r->decoded_content);
   $data->{_cache} = $self->_cache_meta($r);
   _spew($cache, encode_json($data));
   $self->_ingest($data);
   return;
}

sub _ua ($self)
{
   my $ua = LWP::UserAgent->new(
      timeout => $self->{timeout},
      agent   => "p5-Weather-METNO/$VERSION " . ($self->{uid} // 'unknown') . ' ',
   );
   $ua->default_header(Accept => 'application/json');
   $ua->default_header('Accept-Encoding' => HTTP::Message::decodable);
   return $ua;
}

sub _url ($self)
{
   my $url = sprintf '%s?lat=%.4f&lon=%.4f', $API_URL, $self->{lat}, $self->{lon};
   $url .= '&altitude=' . $self->{alt} if defined $self->{alt};
   return $url;
}

sub _cache_file ($self)
{
   my $name = sprintf 'metno_%.4f_%.4f', $self->{lat}, $self->{lon};
   $name .= '_' . $self->{alt} if defined $self->{alt};
   $name =~ tr/-/m/;
   return File::Spec->catfile($self->{cache_dir}, "$name.json");
}

sub _cache_meta ($self, $r, $prev = {})
{
   return {
      last_modified => $r->header('Last-Modified') // $prev->{last_modified},
      expires       => str2time($r->header('Expires')) // $prev->{expires},
   };
}

sub _ingest ($self, $data)
{
   croak 'Unexpected JSON' unless $data->{properties}{meta}{updated_at};

   $self->{data}          = $data;
   $self->{updated_at}    = _iso_to_epoch($data->{properties}{meta}{updated_at});
   $self->{expires}       = $data->{_cache}{expires};
   $self->{last_modified} = $data->{_cache}{last_modified};
   $self->{weather}       = {};
   $self->{times}         = [];

   for my $point ($data->{properties}{timeseries}->@*)
   {
      my $epoch = _iso_to_epoch($point->{time});
      push $self->{times}->@*, $epoch;
      $self->{weather}{$epoch} = $point->{data};
   }

   $self->{closest} = $self->_at_or_after($self->_now);
   return;
}

sub _load_symbols ($self)
{
   (my $path = __FILE__) =~ s/\.pm$//;
   $path = File::Spec->catfile($path, 'legends.json');
   croak "bundled legends.json missing: $path" unless -f $path;
   $self->{symbols} = decode_json(_slurp($path));
   return;
}

sub _now ($self) { $self->{now} // time }

sub _at_or_after ($self, $target)
{
   for my $t ($self->{times}->@*)
   {
      return $t if $t >= $target;
   }
   return $self->{times}[-1];
}

### time travel (same getters, different datapoint)

# Closest timeseries point at or after $epoch.
sub at ($self, $epoch)
{
   my $clone = bless { %$self }, ref $self;
   $clone->{closest} = $self->_at_or_after($epoch);
   return $clone;
}

# Same, relative to now: $w->in(hours => 6)->temp_c
sub in ($self, %args)
{
   my $delta = ($args{days} // 0) * 86400
             + ($args{hours} // 0) * 3600
             + ($args{minutes} // 0) * 60;
   return $self->at($self->_now + $delta);
}

# One object per timeseries step, getters still work.
sub steps ($self)
{
   return map { $self->at($_) } $self->{times}->@*;
}

sub times ($self) { $self->{times}->@* }

### instant

sub forecast_time ($self) { $self->{closest} }
sub updated_at    ($self) { $self->{updated_at} }
sub expires       ($self) { $self->{expires} }
sub stale         ($self) { ($self->{expires} // 0) <= $self->_now }

sub temp_c ($self) { $self->_instant('air_temperature') }
sub temp_f ($self) { _c_to_f($self->temp_c) }

sub temp_apparent_c ($self) { $self->_instant('apparent_air_temperature') }
sub temp_apparent_f ($self) { _c_to_f($self->temp_apparent_c) }

sub temp_p10 ($self) { $self->_instant('air_temperature_percentile_10') }
sub temp_p90 ($self) { $self->_instant('air_temperature_percentile_90') }

sub humidity    ($self) { $self->_instant('relative_humidity') }
sub airpressure ($self) { $self->_instant('air_pressure_at_sea_level') }
sub dewpoint    ($self) { $self->_instant('dew_point_temperature') }
sub uvindex     ($self) { $self->_instant('ultraviolet_index_clear_sky') }

sub cloudiness    ($self) { $self->_instant('cloud_area_fraction') }
sub clouds_low    ($self) { $self->_instant('cloud_area_fraction_low') }
sub clouds_medium ($self) { $self->_instant('cloud_area_fraction_medium') }
sub clouds_high   ($self) { $self->_instant('cloud_area_fraction_high') }
sub foginess      ($self) { $self->_instant('fog_area_fraction') }

sub windspeed_ms ($self) { $self->_instant('wind_speed') }
sub windspeed_kmh ($self)
{
   my $ms = $self->windspeed_ms;
   return unless defined $ms;
   return 0 + sprintf('%.1f', $ms * 3.6);
}
sub windspeed_bft ($self)
{
   my $ms = $self->windspeed_ms;
   return unless defined $ms;
   return 0 + sprintf('%.0f', ($ms / 0.836) ** (2/3));
}
sub windspeed_bft_txt ($self)
{
   my $bft = $self->windspeed_bft;
   return unless defined $bft;
   return $self->bft_to_txt($bft);
}

sub windspeed_gust_ms ($self) { $self->_instant('wind_speed_of_gust') }
sub windspeed_gust_kmh ($self)
{
   my $ms = $self->windspeed_gust_ms;
   return unless defined $ms;
   return 0 + sprintf('%.1f', $ms * 3.6);
}

sub windspeed_p10_ms ($self) { $self->_instant('wind_speed_percentile_10') }
sub windspeed_p90_ms ($self) { $self->_instant('wind_speed_percentile_90') }

sub windfrom_deg ($self) { $self->_instant('wind_from_direction') }
sub windfrom_dir ($self)
{
   my $deg = $self->windfrom_deg;
   return unless defined $deg;
   return $self->get_direction($deg);
}
sub windfrom_dir_utf8arrow ($self)
{
   my $deg = $self->windfrom_deg;
   return unless defined $deg;
   return $self->get_direction($deg, 1);
}

### period (next_1_hours, falling back to 6h/12h)

sub symbol ($self)
{
   return $self->_summary('symbol_code');
}

sub symbol_txt ($self)
{
   my $sym = $self->symbol or return;
   my $base = (split /_/, $sym)[0];
   return $self->{symbols}{$base}{'desc_' . $self->{lang}};
}

sub symbol_url ($self, $ext = 'png')
{
   my $sym = $self->symbol or return;
   return "$ICON_URL/$sym.$ext";
}

sub symbol_confidence ($self)
{
   return $self->_summary('symbol_confidence');
}

sub precip ($self)      { $self->_period('precipitation_amount') }
sub precip_min ($self)  { $self->_period('precipitation_amount_min') }
sub precip_max ($self)  { $self->_period('precipitation_amount_max') }
sub precip_prob ($self) { $self->_period('probability_of_precipitation') }
sub thunder_prob ($self){ $self->_period('probability_of_thunder') }

sub temp_min_c ($self) { $self->_period('air_temperature_min', qw(next_6_hours next_12_hours)) }
sub temp_max_c ($self) { $self->_period('air_temperature_max', qw(next_6_hours next_12_hours)) }

sub as_string ($self)
{
   return sprintf(
      '%.1f°C (%.1f°F) :: %s :: Cld: %u%% :: Hum: %u%% :: Fog: %u%% :: UV: %.1f :: Wnd: %s from %s',
      $self->temp_c // 0,
      $self->temp_f // 0,
      $self->symbol_txt // 'n/a',
      $self->cloudiness // 0,
      $self->humidity // 0,
      $self->foginess // 0,
      $self->uvindex // 0,
      $self->windspeed_bft_txt // 'n/a',
      $self->windfrom_dir // 'n/a',
   );
}

### internals

sub _instant ($self, $key)
{
   return $self->{weather}{$self->{closest}}{instant}{details}{$key};
}

sub _period ($self, $key, @prefs)
{
   @prefs = qw(next_1_hours next_6_hours next_12_hours) unless @prefs;
   my $d = $self->{weather}{$self->{closest}} or return;
   for my $p (@prefs)
   {
      return $d->{$p}{details}{$key} if exists $d->{$p}{details}{$key};
   }
   return;
}

sub _summary ($self, $key, @prefs)
{
   @prefs = qw(next_1_hours next_6_hours next_12_hours) unless @prefs;
   my $d = $self->{weather}{$self->{closest}} or return;
   for my $p (@prefs)
   {
      return $d->{$p}{summary}{$key} if exists $d->{$p}{summary}{$key};
   }
   return;
}

sub get_direction ($self, $deg, $type = 0) # 0 = txt, 1 = unicode arrow
{
   my @text  = qw(N NbE NNE NEbN NE NEbE ENE EbN E EbS ESE SEbE SE SEbS SSE SbE S SbW SSW SWbS SW SWbW WSW WbS W WbN WNW NWbW NW NWbN NNW NbW);
   my @arrow = ("\N{UPWARDS BLACK ARROW}", "\N{NORTH EAST ARROW}", "\N{RIGHTWARDS BLACK ARROW}", "\N{SOUTH EAST ARROW}", "\N{DOWNWARDS BLACK ARROW}", "\N{SOUTH WEST ARROW}", "\N{LEFTWARDS BLACK ARROW}", "\N{NORTH WEST ARROW}");
   my $n     = $type ? 8 : 32;
   my $dir   = int((($deg % 360) / (360 / $n)) + 0.5) % $n;
   return $type ? $arrow[$dir] : $text[$dir];
}

sub bft_to_txt ($self, $bft)
{
   my @txt = ('Calm', 'Light air', 'Light breeze', 'Gentle breeze', 'Moderate breeze', 'Fresh breeze', 'Strong breeze', 'High wind', 'Gale', 'Strong gale', 'Storm', 'Violent storm', 'Hurricane');
   return $txt[$bft <= 12 ? $bft : 12];
}

sub _iso_to_epoch ($iso)
{
   $iso =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/
      or croak "bad timestamp: $iso";
   return timegm($6, $5, $4, $3, $2 - 1, $1);
}

sub _c_to_f ($c)
{
   return unless defined $c;
   return 0 + sprintf('%.1f', ($c * 9 / 5) + 32);
}

sub _slurp ($path)
{
   open my $fh, '<:raw', $path or croak "read $path: $!";
   local $/;
   return scalar <$fh>;
}

sub _spew ($path, $bytes)
{
   open my $fh, '>:raw', $path or croak "write $path: $!";
   print {$fh} $bytes;
}

1;

__END__

=encoding utf8

=head1 NAME

Weather::METNO - tiny client for the met.no locationforecast 2.0 API

=head1 SYNOPSIS

    use Weather::METNO;
    my $w = Weather::METNO->new(
        lat => 52.52,
        lon => 13.41,
        lang => 'en',
        uid  => 'you@example.com',
    );
    say $w->as_string;
    say $w->in(hours => 6)->temp_c;

=head1 DESCRIPTION

Fetches the MET Norway locationforecast and exposes the closest future
datapoint through plain getters. Same idea as before, plus:

=over 4

=item * instance state (two objects no longer clobber each other)

=item * local cache honoring C<Expires> / C<If-Modified-Since> (met.no TOS)

=item * C<next_1_hours> falls back to 6h/12h so later steps don't die

=item * C<at> / C<in> / C<steps> to walk the 9-day series

=item * bundled C<legends.json> (WeatherIcon API is gone)

=back

A unique User-Agent string is required by met.no. Pass your domain or email
as C<uid>.

=head1 METHODS

=head2 new

    Weather::METNO->new(lat => $lat, lon => $lon, uid => $ua, lang => 'en', alt => 40, timeout => 5);

Coordinates are truncated to 4 decimals (TOS). C<alt> is metres above sea level.

=head2 as_string

The one-liner from the README.

=head2 Instant

C<temp_c>, C<temp_f>, C<temp_apparent_c>, C<temp_apparent_f>, C<temp_p10>,
C<temp_p90>, C<humidity>, C<airpressure>, C<dewpoint>, C<uvindex>,
C<cloudiness>, C<clouds_low>, C<clouds_medium>, C<clouds_high>, C<foginess>,
C<windspeed_ms>, C<windspeed_kmh>, C<windspeed_bft>, C<windspeed_bft_txt>,
C<windspeed_gust_ms>, C<windspeed_gust_kmh>, C<windspeed_p10_ms>,
C<windspeed_p90_ms>, C<windfrom_deg>, C<windfrom_dir>,
C<windfrom_dir_utf8arrow>.

=head2 Period

C<symbol>, C<symbol_txt>, C<symbol_url>, C<symbol_confidence>,
C<precip>, C<precip_min>, C<precip_max>, C<precip_prob>, C<thunder_prob>,
C<temp_min_c>, C<temp_max_c>.

Missing optional fields return C<undef> instead of dying.

=head2 Timeseries

=over 4

=item C<forecast_time> — epoch of the selected datapoint

=item C<updated_at> — model update epoch

=item C<expires> / C<stale> — from the HTTP Expires header

=item C<at($epoch)> — clone pinned to that (or next) step

=item C<in(hours =E<gt> 6, days =E<gt> 1)> — same, relative to now

=item C<steps> — list of clones, one per timeseries step

=item C<times> — list of epochs

=back

=head1 SEE ALSO

L<https://api.met.no/weatherapi/locationforecast/2.0/documentation>

=cut
