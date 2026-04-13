package Bibliomation::Shared::Logging;

use strict;
use warnings;
use POSIX qw(strftime);
use Exporter 'import';

our @EXPORT_OK = qw(setup_logger configure_logger log_message log_header DEBUG INFO WARN ERROR FATAL);

use constant LINE_WIDTH => 120;
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

    $log_file = undef;
    return unless defined $path && $path ne '';

    $log_file = $path;
    return if -e $log_file;

    open my $fh, '>', $log_file or die "Could not create log file '$log_file': $!";
    close $fh;
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
    return $LEVEL_PRIORITY{uc($level // INFO)} // $LEVEL_PRIORITY{INFO};
}

sub log_header {
    my ($level, $title, $message) = @_;
    my $log_msg = _construct_header($level, $title, $message);
    _write_log($log_msg, $level);
    return $log_msg;
}

sub log_message {
    my ($level, $message) = @_;
    my $log_msg = _construct_log_message($level, $message);
    _write_log($log_msg, $level);
    return $log_msg;
}

sub _center_line {
    my ($text, $inner_width) = @_;
    $text //= '';
    $text =~ s/\R/ /g;
    $text = substr($text, 0, $inner_width) if length($text) > $inner_width;

    my $pad_left  = int(($inner_width - length($text)) / 2);
    my $pad_right = $inner_width - length($text) - $pad_left;

    return '|' . (' ' x $pad_left) . $text . (' ' x $pad_right) . "|\n";
}

sub _wrap_lines {
    my ($text, $inner_width) = @_;
    $text //= '';
    return () if $inner_width < 1;

    my @out;

    for my $paragraph (split(/\R/, $text)) {
        $paragraph =~ s/\s+/ /g;
        $paragraph =~ s/^\s+|\s+$//g;

        if ($paragraph eq '') {
            push @out, '|' . (' ' x $inner_width) . "|\n";
            next;
        }

        my $line = '';
        for my $word (split(/ /, $paragraph)) {
            if (length($word) > $inner_width) {
                if ($line ne '') {
                    push @out, '|' . sprintf("%-*s", $inner_width, $line) . "|\n";
                    $line = '';
                }

                while (length($word) > $inner_width) {
                    push @out, '|' . substr($word, 0, $inner_width) . "|\n";
                    $word = substr($word, $inner_width);
                }

                $line = $word;
                next;
            }

            if ($line eq '') {
                $line = $word;
            } elsif (length($line) + 1 + length($word) <= $inner_width) {
                $line .= " $word";
            } else {
                push @out, '|' . sprintf("%-*s", $inner_width, $line) . "|\n";
                $line = $word;
            }
        }

        push @out, '|' . sprintf("%-*s", $inner_width, $line) . "|\n" if $line ne '';
    }

    return @out;
}

sub _construct_header {
    my ($level, $title, $message) = @_;
    my $timestamp   = strftime('%Y-%m-%d %H:%M:%S', localtime);
    my $inner_width = LINE_WIDTH - 2;
    my $normalized  = uc($level // INFO);

    $normalized = INFO unless exists $LEVEL_PRIORITY{$normalized};
    return sprintf("[%s] [%s] %s %s\n", $timestamp, $normalized, $title // '', $message // '') if $inner_width < 1;

    my $border  = '+' . ('=' x $inner_width) . "+\n";
    my $divider = '|' . ('-' x $inner_width) . "|\n";
    my $meta    = sprintf("[%s] [%s]", $timestamp, $normalized);
    my $pad     = $inner_width > 2 ? 1 : 0;
    my $body_width = $inner_width - (2 * $pad);

    my @lines = ($border, _center_line($meta, $inner_width));

    if (defined $title && $title ne '') {
        push @lines, $divider, _center_line($title, $inner_width);
    }

    push @lines, $divider;

    for my $line (_wrap_lines($message // '', $body_width)) {
        my $content = substr($line, 1, $body_width);
        push @lines, '|' . (' ' x $pad) . $content . (' ' x $pad) . "|\n";
    }

    push @lines, $border;
    return join('', @lines);
}

sub _construct_log_message {
    my ($level, $message) = @_;
    my $timestamp  = strftime('%Y-%m-%d %H:%M:%S', localtime);
    my $normalized = uc($level // INFO);

    $normalized = INFO unless exists $LEVEL_PRIORITY{$normalized};

    my $prefix      = "[$timestamp] [$normalized] ";
    my $prefix_len  = length($prefix);
    my $line_width  = LINE_WIDTH;
    my $inner_width = $line_width - $prefix_len;

    return $prefix . ($message // '') . "\n" if $inner_width < 1;

    my @lines = _wrap_lines($message // '', $inner_width);
    return $prefix . "\n" unless @lines;

    my @formatted;
    for my $i (0 .. $#lines) {
        my $content = substr($lines[$i], 1, $inner_width);
        chomp $content;
        if ($i == 0) {
            push @formatted, $prefix . $content . "\n";
        } else {
            push @formatted, (' ' x $prefix_len) . $content . "\n";
        }
    }

    return join('', @formatted);
}

sub _write_log {
    my ($log_msg, $level) = @_;
    return unless defined $log_msg;

    my $priority = _level_value($level);

    if (defined $log_file && $priority >= _level_value($file_log_level)) {
        open my $fh, '>>', $log_file or die "Could not open log file '$log_file': $!";
        print {$fh} $log_msg;
        close $fh;
    }

    if ($console_enabled && $priority >= _level_value($console_log_level)) {
        print $log_msg;
    }
}

1;
