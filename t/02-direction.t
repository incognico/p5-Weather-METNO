use 5.24.0;
use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Weather::METNO;

my $w = bless {}, 'Weather::METNO';

is $w->get_direction(0),   'N';
is $w->get_direction(360), 'N';
is $w->get_direction(90),  'E';
is $w->get_direction(180), 'S';
is $w->get_direction(270), 'W';
is $w->get_direction(45),  'NE';
is $w->get_direction(359), 'N';

is $w->get_direction(0, 1),   "\N{UPWARDS BLACK ARROW}";
is $w->get_direction(90, 1),  "\N{RIGHTWARDS BLACK ARROW}";
is $w->get_direction(180, 1), "\N{DOWNWARDS BLACK ARROW}";
is $w->get_direction(270, 1), "\N{LEFTWARDS BLACK ARROW}";
is $w->get_direction(360, 1), "\N{UPWARDS BLACK ARROW}";

is $w->bft_to_txt(0),  'Calm';
is $w->bft_to_txt(8),  'Gale';
is $w->bft_to_txt(12), 'Hurricane';
is $w->bft_to_txt(99), 'Hurricane';

done_testing;
