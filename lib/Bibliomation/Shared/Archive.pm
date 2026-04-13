package Bibliomation::Shared::Archive;

use strict;
use warnings;
use Archive::Tar;
use Exporter 'import';
use File::Basename qw(basename dirname);

our @EXPORT_OK = qw(create_tar_gz_archive);

sub create_tar_gz_archive {
    my (%args) = @_;

    my $files         = $args{files};
    my $output_path   = $args{output_path};
    my $member_paths  = $args{member_paths};
    my $preserve_paths = $args{preserve_paths} ? 1 : 0;

    die "create_tar_gz_archive: 'files' must be an arrayref\n" unless ref($files) eq 'ARRAY';
    die "create_tar_gz_archive: 'files' must include at least one path\n" unless @$files;
    die "create_tar_gz_archive: 'output_path' is required\n" unless defined $output_path && $output_path ne '';
    die "create_tar_gz_archive: 'member_paths' must be an arrayref when provided\n"
        if defined $member_paths && ref($member_paths) ne 'ARRAY';
    die "create_tar_gz_archive: 'member_paths' must match the number of files\n"
        if defined $member_paths && @$member_paths != @$files;

    my $output_dir = dirname($output_path);
    die "create_tar_gz_archive: output directory not found: $output_dir\n" unless -d $output_dir;

    my $tar = Archive::Tar->new();

    for my $index (0 .. $#$files) {
        my $local_path = $files->[$index];
        die "create_tar_gz_archive: local file not found: $local_path\n" unless defined $local_path && -f $local_path;

        my $member_name =
            defined $member_paths ? $member_paths->[$index]
          : $preserve_paths      ? _normalize_member_path($local_path)
          :                        basename($local_path);

        die "create_tar_gz_archive: archive member name is required for file: $local_path\n"
            unless defined $member_name && $member_name ne '';

        $member_name = _normalize_member_path($member_name);

        open my $fh, '<:raw', $local_path or die "Cannot read file '$local_path': $!\n";
        my $content = do { local $/; <$fh> };
        close $fh;

        $tar->add_data($member_name, $content);
    }

    my $written = $tar->write($output_path, COMPRESS_GZIP);
    die "create_tar_gz_archive: failed to write archive '$output_path'\n" unless $written;

    return $output_path;
}

sub _normalize_member_path {
    my ($path) = @_;
    $path =~ s{\\}{/}g;
    $path =~ s{^[A-Za-z]:/}{};
    $path =~ s{^/+}{};
    return $path;
}

1;
