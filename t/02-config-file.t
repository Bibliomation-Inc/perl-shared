use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);

use Bibliomation::Shared::ConfigFile qw(load_config);

sub exception (&);

my ($fh, $path) = tempfile();
print {$fh} <<'CFG';
# comment
host = localhost
port = 5432
user = "evergreen"
password = 'secret'
blank = value
CFG
close $fh;

my $cfg = load_config($path);
is($cfg->{host}, 'localhost', 'parses unquoted value');
is($cfg->{port}, '5432', 'parses numeric-like value as string');
is($cfg->{user}, 'evergreen', 'parses double-quoted value');
is($cfg->{password}, 'secret', 'parses single-quoted value');
is($cfg->{blank}, 'value', 'parses additional key');

like(
    exception { load_config('definitely_missing_file.conf') },
    qr/Configuration file not found/,
    'dies on missing file'
);

my ($fh_bad, $bad_path) = tempfile();
print {$fh_bad} "invalid line without equals\n";
close $fh_bad;

like(
    exception { load_config($bad_path) },
    qr/Invalid configuration at line 1/,
    'dies on invalid config line'
);

done_testing();

sub exception (&) {
    my $code = shift;
    eval { $code->(); 1 };
    return $@;
}
