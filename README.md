# p5-Weather-METNO
Uses the [met.no](https://www.met.no/) locationforecast 2.0 (beta) API (https://api.met.no/weatherapi/locationforecast/2.0/documentation)

Fetches the weather forecast and lets you access the data for the closest data point in the future.

Example:
```perl
use Weather::METNO;
my $w = Weather::METNO->new(lat => $lat, lon => $lon, lang => 'en', uid => '<your@email.addr>');
say sprintf(%.1f°C / %.1f°F :: %s :: Cld: %u%% :: Hum: %u%% :: Fog: %u%% :: Wnd: %s km/h from %s", $w->temp_c, $w->temp_f, $w->symbol_txt, $w->cloudiness, $w->humidity, $w->foginess, $w->windspeed, $w->windfromdir);
```

A unique string in the user agent is required per met.no TOS, it should preferably be your domain or your email address. `uid` will get appeneded the to LWP's UA string.

The legend json for the symbols is currently set to `https://distfiles.lifeisabug.com/metno/legends.json` (a cached version I keep) instead of `https://api.met.no/weatherapi/weathericon/2.0/legends` because those are probably not updated very often. The API 2.0 symbol icons are meant to be self-hosted instead of being API provided, if you want to use those feel free to embed them from `https://distfiles.lifeisabug.com/metno/`
