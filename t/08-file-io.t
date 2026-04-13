use strict;
use warnings;
use Test::More;
use File::Spec;
use File::Temp qw(tempdir);

use Bibliomation::Shared::FileIO qw(
    read_text_file
    write_text_file
    append_text_file
    write_delimited_file
);

sub exception (&) {
    my $code = shift;
    eval { $code->(); 1 };
    return $@;
}

my $tempdir = tempdir(CLEANUP => 1);

my $text_path = File::Spec->catfile($tempdir, 'example.txt');
write_text_file(
    path    => $text_path,
    content => "first line\n",
);
append_text_file(
    path    => $text_path,
    content => "second line\n",
);

is(
    read_text_file($text_path),
    "first line\nsecond line\n",
    'write_text_file and append_text_file produce readable output',
);

my $tsv_path = File::Spec->catfile($tempdir, 'export.tsv');
write_delimited_file(
    path    => $tsv_path,
    columns => [qw(id note)],
    rows    => [
        [1, "Hello\nWorld"],
        [2, undef],
    ],
);

is(
    read_text_file($tsv_path),
    "id\tnote\n1\tHello World\n2\t\n",
    'write_delimited_file writes TSV output and sanitizes newlines by default',
);

my $csv_path = File::Spec->catfile($tempdir, 'quoted.csv');
write_delimited_file(
    path         => $csv_path,
    delimiter    => ',',
    quote_fields => 1,
    rows         => [
        ['alpha,beta', 'he said "hi"'],
    ],
);

is(
    read_text_file($csv_path),
    "\"alpha,beta\",\"he said \"\"hi\"\"\"\n",
    'write_delimited_file can quote delimiter and quote characters',
);

like(
    exception {
        write_delimited_file(
            path => File::Spec->catfile($tempdir, 'bad.tsv'),
            rows => ['not-an-arrayref'],
        );
    },
    qr/each row must be an arrayref/,
    'dies when a row is not an arrayref',
);

done_testing();
