package Weather::METNO;

use 5.24.0;

use utf8;
use strict;
use warnings;

use feature 'signatures';
no warnings qw(experimental::signatures experimental::smartmatch);

use Carp;
use DateTime::Format::ISO8601;
use File::Slurp;
use JSON::MaybeXS;
use LWP::UserAgent;
use POSIX 'floor';

our $VERSION = 9999;

my $self;

my ($data, @times, $weather, $closest, $symbols);

my $api_ver = '2.0';
my $api_url = 'https://api.met.no/weatherapi/locationforecast/'.$api_ver.'/complete';
my $sym_url = 'https://api.met.no/weatherapi/weathericon/'.$api_ver.'/legends';
my $sym_tmp = '/tmp/lwp-metno-legends.json';
my $sym_sec = 604800; # seconds to $sym_tmp expiry

sub new ($class, %args)
{
   my $self = bless({}, $class);

   $self->{uid} = $args{uid} || croak 'A unique identifier in the UA is required per TOS, best to set it to your domain/email.';

   $self->{lat} = $args{lat} // croak 'lat not specified';
   $self->{lon} = $args{lon} // croak 'lon not specified';
   $self->{alt} = $args{alt};

   $self->{lang}    = defined $args{lang}    ? $args{lang}    : 'en';
   $self->{timeout} = defined $args{timeout} ? $args{timeout} : 5;

   $self->fetch_weather;
 
   return $self;
}

sub fetch_weather ($self)
{
   my $ua = LWP::UserAgent->new(timeout => $self->{timeout}, agent => 'p5-Weather-METNO '.$self->{uid}.' ');
   $ua->default_header('Accept' => 'application/json');

   unless (-f $sym_tmp && (time - (stat($sym_tmp))[10]) < $sym_sec)
   {
      my $r = $ua->mirror($sym_url, $sym_tmp);
      croak $r->status_line unless ($r->is_success || $r->code == 304);
      utime(undef, undef, $sym_tmp) if ($r->code == 304);
   }

   $symbols = decode_json(read_file($sym_tmp));

   $ua->default_header('Accept-Encoding' => HTTP::Message::decodable);

   my $url = $api_url . '?lat=' . sprintf('%.2f', $self->{lat}) . '&lon=' . sprintf('%.2f', $self->{lon}) . (defined $self->{alt} ? ('&altitude=' . int($self->{alt})) : '');

   my $r = $ua->get($url);
   croak $r->status_line unless ($r->is_success);
   $data = decode_json($r->decoded_content);

   croak 'Unexpected JSON' unless (exists $$data{properties}{meta}{updated_at});

   my $fmt = DateTime::Format::ISO8601->new;

   for ($$data{properties}{timeseries}->@*)
   {
      my $epoch = $fmt->parse_datetime($$_{time})->epoch;

      push(@times, $epoch);

      $$weather{$epoch} = $$_{data};
   }

   for (sort {$a <=> $b} @times)
   {
      next if ($_ < time);
      $closest = $_;
      last;
   }

   return;
}

###

sub forecast_time ($self)
{
   return $closest;
}

sub updated_at ($self)
{
   return DateTime::Format::ISO8601->parse_datetime($$data{properties}{meta}{updated_at})->epoch;
}

sub temp_c ($self)
{
   return $$weather{$closest}{instant}{details}{air_temperature};
}

sub temp_f ($self)
{
   return sprintf('%.1f', (($self->temp_c*9/5)+32));
}

sub humidity ($self)
{
   return $$weather{$closest}{instant}{details}{relative_humidity};
}

sub airpressure ($self)
{
   return $$weather{$closest}{instant}{details}{air_pressure_at_sea_level};
}

sub windspeed_ms ($self)
{
   return $$weather{$closest}{instant}{details}{wind_speed};
}

sub windspeed_kmh ($self)
{
   return sprintf('%.1f', ($self->windspeed_ms*3.6));
}

sub windspeed_bft ($self)
{
   return sprintf('%.0f', (($self->windspeed_ms/0.836)**(2/3)));
}

sub windspeed_bft_txt ($self)
{
   return $self->bft_to_txt($self->windspeed_bft);
}

sub windspeed_gust_ms ($self)
{
   return $$weather{$closest}{instant}{details}{wind_speed_of_gust};
}

sub windspeed_gust_kmh ($self)
{
   return sprintf('%.1f', ($self->windspeed_gust_ms*3.6));
}

sub windfrom_deg ($self)
{
   return $$weather{$closest}{instant}{details}{wind_from_direction};
}

sub windfrom_dir ($self)
{
   return $self->get_direction($self->windfrom_deg);
}

sub windfrom_dir_utf8arrow ($self)
{
   return $self->get_direction($self->windfrom_deg, 1);
}

sub cloudiness ($self)
{
   return $$weather{$closest}{instant}{details}{cloud_area_fraction};
}

sub dewpoint ($self)
{
   return $$weather{$closest}{instant}{details}{dew_point_temperature};
}

sub foginess ($self)
{
   return $$weather{$closest}{instant}{details}{fog_area_fraction};
}

sub uvindex ($self)
{
   return $$weather{$closest}{instant}{details}{ultraviolet_index_clear_sky};
}

sub symbol ($self)
{
   return $$weather{$closest}{next_1_hours}{summary}{symbol_code};
}

sub symbol_txt ($self)
{
   return $$symbols{(split(/_/, $self->symbol))[0]}{'desc_'.$self->{lang}};
}

sub precip ($self)
{
   return $$weather{$closest}{next_1_hours}{details}{precipitation_amount};
}

###

sub get_direction ($self, $deg, $type = 0) # 0 = txt, 1 = unicode arrow
{
   my @text  = qw(N NbE NNE NEbN NE NEbE ENE EbN E EbS ESE SEbE SE SEbS SSE SbE S SbW SSW SWbS SW SWbW WSW WbS W WbN WNW NWbW NW NWbN NNW NbW);
   my @arrow = ("\N{UPWARDS BLACK ARROW}", "\N{NORTH EAST ARROW}", "\N{RIGHTWARDS BLACK ARROW}", "\N{SOUTH EAST ARROW}", "\N{DOWNWARDS BLACK ARROW}", "\N{SOUTH WEST ARROW}", "\N{LEFTWARDS BLACK ARROW}", "\N{NORTH WEST ARROW}");
   my $dir   = floor($deg/360*($type ? 8 : 32));

   return $type ? $arrow[$dir] : $text[$dir];
}

sub bft_to_txt ($self, $bft)
{
   my @txt = ('Calm', 'Light air', 'Light breeze', 'Gentle breeze', 'Moderate breeze', 'Fresh breeze', 'Strong breeze', 'High wind', 'Gale', 'Strong gale', 'Storm', 'Violent storm', 'Hurricane');

   return $txt[$bft <= 12 ? $bft : 12];
}

1;
