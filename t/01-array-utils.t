use strict;
use warnings;
use Test::More;

use Bibliomation::Shared::ArrayUtils qw(dedupe_array);

my $deduped = dedupe_array([3, 1, 3, 2, 1]);
is_deeply($deduped, [1, 2, 3], 'dedupe_array removes duplicates and sorts');

my $empty = dedupe_array([]);
is_deeply($empty, [], 'dedupe_array handles empty array');

my $undef_input = dedupe_array(undef);
is_deeply($undef_input, [], 'dedupe_array handles undef input');

done_testing();
