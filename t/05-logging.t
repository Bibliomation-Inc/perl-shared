use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);

use Bibliomation::Shared::Logging qw(setup_logger configure_logger log_message log_header INFO WARN ERROR);

my ($fh, $log_path) = tempfile();
close $fh;

setup_logger($log_path);
configure_logger(
    console       => 1,
    file_level    => 'DEBUG',
    console_level => 'WARN',
);

my $stdout = '';
{
    open my $stdout_fh, '>', \$stdout or die "Could not capture STDOUT: $!";
    local *STDOUT = $stdout_fh;

    my $info_line = log_message(INFO, 'file only');
    like($info_line, qr/\[INFO\] file only/, 'log_message returns formatted INFO line');

    my $header = log_header(ERROR, 'Worker Failed', "First line\nSecond line");
    like($header, qr/Worker Failed/, 'log_header returns formatted header output');
}

my $log_contents = do {
    open my $in, '<', $log_path or die "Could not read log file: $!";
    local $/;
    <$in>;
};

like($log_contents, qr/\[INFO\] file only/, 'INFO message is written to the log file');
like($log_contents, qr/Worker Failed/, 'header output is written to the log file');
unlike($stdout, qr/\[INFO\] file only/, 'INFO message is filtered from console output');
like($stdout, qr/\[ERROR\]/, 'ERROR header reaches console output');
like($stdout, qr/Second line/, 'header output preserves multi-line message text');

done_testing();
