# p5-Weather-METNO

Tiny Perl client for the [met.no](https://www.met.no/) locationforecast 2.0 API
([docs](https://api.met.no/weatherapi/locationforecast/2.0/documentation)).

Fetches the forecast, caches it like the TOS wants, and lets you read the
closest future datapoint — or walk the rest of the 9-day series with the
same getters.

```perl
use Weather::METNO;
my $w = Weather::METNO->new(lat => $lat, lon => $lon, lang => 'en', uid => '<your@email.addr>');
say $w->as_string;
# 20.5°C (68.9°F) :: Fair :: Cld: 42% :: Hum: 55% :: Fog: 0% :: UV: 1.2 :: Wnd: Light breeze from N

say $w->in(hours => 6)->temp_c;
say $w->precip_prob;          # % chance of rain in the next hour
say $w->temp_apparent_c;      # feels-like, from the model
```

```bash
perl examples/now.pl 52.52 13.41 you@example.com
```

A unique string in the user agent is required per met.no TOS — preferably
your domain or email, in case they need to reach you. `uid` is appended to
the UA.

Responses are cached under `$TMPDIR` (or `METNO_CACHE`) and not re-fetched
until `Expires`. Repeat requests send `If-Modified-Since`. Coordinates are
truncated to 4 decimals.

Symbol icons are meant to be self-hosted; `$w->symbol_url` points at
`https://distfiles.lifeisabug.com/metno/` if you want the hosted set.

See `lib/Weather/METNO.pm` for the full method list. Pull requests welcome.
