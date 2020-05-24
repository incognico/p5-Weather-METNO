package Weather::METNO;

our $VERSION = "git";

use 5.28.0;

use utf8;
use strict;
use warnings;

use feature 'signatures';
no warnings qw(experimental::signatures experimental::smartmatch);

use Carp;
use JSON::MaybeXS;
use LWP::UserAgent;
use DateTime;
use DateTime::Format::Strptime;
use POSIX qw(floor);

my $self;

my (@times, $weather, $closest, $symbols);

my $api_ver = '2.0';
my $api_url = 'https://api.met.no/weatherapi/locationforecast/' . $api_ver;
my $sym_url = 'https://distfiles.lifeisabug.com/metno/legends.json';

sub new ($class, %args)
{
   my $self = bless({}, $class);

   $self->{uid} = $args{uid} || croak 'A unique identifier in the UA is required per TOS, best to set it to your domain/email.';

   $self->{lat} = $args{lat} // croak 'lat not specified';
   $self->{lon} = $args{lon} // croak 'lon not specified';
   $self->{alt} = $args{alt};

   $self->{lang}    = defined $args{lang}    ? $args{lang}    : 'en';
   $self->{timeout} = defined $args{timeout} ? $args{timeout} : 5;

   $self->fetch_weather();
 
   return $self;
}

sub fetch_weather ($self)
{
   my $ua = LWP::UserAgent->new(timeout => $self->{timeout});
   $ua->default_header('Accept' => 'application/json');
   $ua->agent($self->{uid}.' ');

   my $url = $api_url . '?lat=' . $self->{lat} . '&lon=' . $self->{lon} . (defined $self->{alt} ? ('&altitude=' . int($self->{alt})) : '');

   say $url;

   my $r = $ua->get($url);
   croak $r->status_line unless ($r->is_success);
   my $data = decode_json($r->decoded_content);

   my $strp = DateTime::Format::Strptime->new(pattern => '%Y-%m-%dT%H:%M:%SZ', time_zone => 'Europe/Oslo', strict => 1);

   for ($$data{properties}{timeseries}->@*)
   {
      my $dt    = $strp->parse_datetime($$_{time});
      my $epoch = $dt->epoch();

      push(@times, $epoch);

      $$weather{$epoch} = $$_{data};
   }

   for (sort {$a <=> $b} @times)
   {
      next if ($_ < time);
      $closest = $_;
      last;
   }

   $r = $ua->get($sym_url);
   croak $r->status_line unless ($r->is_success);
   $symbols = decode_json($r->decoded_content);
}

###

sub temp_c ($self)
{
   return $$weather{$closest}{instant}{details}{air_temperature};
}

sub temp_f ($self)
{
   return sprintf('%.1f', ($self->temp_c*9/5)+32);
}

sub humidity ($self)
{
   return $$weather{$closest}{instant}{details}{relative_humidity};
}

sub windspeed ($self)
{
   return $$weather{$closest}{instant}{details}{wind_speed};
}

sub windfromdeg ($self)
{
   return $$weather{$closest}{instant}{details}{wind_from_direction};
}

sub windfromdir ($self)
{
   return $self->get_direction($self->windfromdeg);
}

sub cloudiness ($self)
{
   return $$weather{$closest}{instant}{details}{cloud_area_fraction};
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
   return $$symbols{(split(/_/, $self->symbol()))[0]}{'desc_'.$self->{lang}};
}
sub precip ($self)
{
   return $$weather{$closest}{next_1_hours}{details}{precipitation_amount};
}

###

sub get_direction ($self, $deg) {
   my @points = qw(N NbE NNE NEbN NE NEbE ENE EbN E EbS ESE SEbE SE SEbS SSE SbE S SbW SSW SWbS SW SWbW WSW WbS W WbN WNW NWbW NW NWbN NNW NbW);

   my $point = floor($deg / 360 * 32);

   return $points[$point];
}

1;
