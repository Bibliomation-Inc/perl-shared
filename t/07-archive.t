use strict;
use warnings;
use Test::More;
use Archive::Tar;
use File::Temp qw(tempdir);
use File::Spec;

use Bibliomation::Shared::Archive qw(create_tar_gz_archive);

sub exception (&) {
    my $code = shift;
    eval { $code->(); 1 };
    return $@;
}

my $tempdir = tempdir(CLEANUP => 1);
my $input_one = File::Spec->catfile($tempdir, 'report.tsv');
my $input_two = File::Spec->catfile($tempdir, 'notes.txt');
my $archive_path = File::Spec->catfile($tempdir, 'bundle.tar.gz');

open my $fh_one, '>:raw', $input_one or die "Cannot create test file: $!";
print {$fh_one} "id\tname\n1\tAlpha\n";
close $fh_one;

open my $fh_two, '>:raw', $input_two or die "Cannot create test file: $!";
print {$fh_two} "second file\n";
close $fh_two;

my $result = create_tar_gz_archive(
    files       => [$input_one, $input_two],
    output_path => $archive_path,
);

is($result, $archive_path, 'create_tar_gz_archive returns output path');
ok(-f $archive_path, 'archive file was created');

my $tar = Archive::Tar->new;
ok($tar->read($archive_path, 1), 'created archive can be read back');
is_deeply(
    [sort map { $_->full_path } $tar->get_files],
    ['notes.txt', 'report.tsv'],
    'archive stores basenames by default',
);

my $custom_archive = File::Spec->catfile($tempdir, 'bundle-custom.tar.gz');
create_tar_gz_archive(
    files        => [$input_one, $input_two],
    output_path  => $custom_archive,
    member_paths => ['exports/report.tsv', 'meta/notes.txt'],
);

my $custom_tar = Archive::Tar->new;
ok($custom_tar->read($custom_archive, 1), 'custom archive can be read back');
is_deeply(
    [sort map { $_->full_path } $custom_tar->get_files],
    ['exports/report.tsv', 'meta/notes.txt'],
    'custom archive member paths are honored',
);

like(
    exception {
        create_tar_gz_archive(
            files       => [],
            output_path => $archive_path,
        );
    },
    qr/'files' must include at least one path/,
    'dies when archive file list is empty',
);

done_testing();
