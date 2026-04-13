package Bibliomation::Shared::Logging;

use strict;
use warnings;
use POSIX qw(strftime);
use Exporter 'import';

our @EXPORT_OK = qw(setup_logger configure_logger log_message DEBUG INFO WARN ERROR FATAL);

use constant {
    DEBUG => 'DEBUG',
    INFO  => 'INFO',
    WARN  => 'WARN',
    ERROR => 'ERROR',
    FATAL => 'FATAL',
};

my %LEVEL_PRIORITY = (
    DEBUG => 1,
    INFO  => 2,
    WARN  => 3,
    ERROR => 4,
    FATAL => 5,
);

my $log_file          = undef;
my $console_enabled   = 1;
my $file_log_level    = 'DEBUG';
my $console_log_level = 'INFO';

sub setup_logger {
    my ($path) = @_;
    return unless defined $path;

    $log_file = $path;
    unless (-e $log_file) {
        open my $fh, '>', $log_file or die "Could not create log file '$log_file': $!";
        close $fh;
    }
}

sub configure_logger {
    my (%opts) = @_;

    $console_enabled   = $opts{console} if exists $opts{console};
    $file_log_level    = uc($opts{file_level}) if exists $opts{file_level};
    $console_log_level = uc($opts{console_level}) if exists $opts{console_level};

    $file_log_level    = 'DEBUG' unless exists $LEVEL_PRIORITY{$file_log_level};
    $console_log_level = 'INFO' unless exists $LEVEL_PRIORITY{$console_log_level};
}

sub _level_value {
    my ($level) = @_;
    my $normalized = uc($level // 'INFO');
    return $LEVEL_PRIORITY{$normalized} // $LEVEL_PRIORITY{INFO};
}

sub log_message {
    my ($level, $message) = @_;
    my $timestamp = strftime('%Y-%m-%d %H:%M:%S', localtime);
    my $line = sprintf("[%s] [%s] %s\n", $timestamp, uc($level // INFO), $message // '');
    my $priority = _level_value($level);

    if (defined $log_file && $priority >= _level_value($file_log_level)) {
        open my $fh, '>>', $log_file or die "Could not open log file '$log_file': $!";
        print $fh $line;
        close $fh;
    }

    if ($console_enabled && $priority >= _level_value($console_log_level)) {
        print $line;
    }

    return $line;
}

1;
