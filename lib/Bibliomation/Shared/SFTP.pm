package Bibliomation::Shared::SFTP;

use strict;
use warnings;
use Net::SFTP::Foreign;
use File::Basename qw(basename);
use Exporter 'import';

our @EXPORT_OK = qw(sftp_upload);

# sftp_upload - Upload one or more local files to a remote SFTP server.
# Arguments (named):
#   host       => remote hostname or IP
#   user       => SFTP username
#   password   => SFTP password
#   remote_dir => remote directory to upload into
#   files      => scalar path or arrayref of paths to upload
# Returns: arrayref of remote paths that were successfully uploaded.
# Throws: on connection failure or upload error.

sub sftp_upload {
    my (%args) = @_;

    my $host       = $args{host}       or die "sftp_upload: 'host' is required\n";
    my $user       = $args{user}       or die "sftp_upload: 'user' is required\n";
    my $password   = $args{password}   or die "sftp_upload: 'password' is required\n";
    my $remote_dir = $args{remote_dir} or die "sftp_upload: 'remote_dir' is required\n";
    my $files      = $args{files}      or die "sftp_upload: 'files' is required\n";

    my @local_files = ref($files) eq 'ARRAY' ? @$files : ($files);

    my $sftp = Net::SFTP::Foreign->new($host, user => $user, password => $password);
    die "SFTP connection to $host failed: " . $sftp->error . "\n" if $sftp->error;

    my @uploaded;
    for my $local_file (@local_files) {
        my $remote_path = "$remote_dir/" . basename($local_file);
        $sftp->put($local_file, $remote_path)
            or die "SFTP upload of '$local_file' to '$remote_path' failed: " . $sftp->error . "\n";
        push @uploaded, $remote_path;
    }

    return \@uploaded;
}

1;