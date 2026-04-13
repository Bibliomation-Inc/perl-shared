package Bibliomation::Shared::FileIO;

use strict;
use warnings;
use Encode qw(encode);
use Exporter 'import';
use File::Basename qw(dirname);

our @EXPORT_OK = qw(read_text_file write_text_file append_text_file write_delimited_file);

sub read_text_file {
    my ($path) = @_;

    die "read_text_file: file path is required\n" unless defined $path && $path ne '';
    die "read_text_file: file not found: $path\n" unless -f $path;

    open my $fh, '<:raw', $path or die "Cannot open file '$path' for reading: $!\n";
    my $content = do { local $/; <$fh> };
    close $fh;

    return $content;
}

sub write_text_file {
    my (%args) = @_;
    return _write_text_file(%args, append => 0);
}

sub append_text_file {
    my (%args) = @_;
    return _write_text_file(%args, append => 1);
}

sub write_delimited_file {
    my (%args) = @_;

    my $path               = $args{path};
    my $rows               = $args{rows};
    my $columns            = $args{columns};
    my $delimiter          = exists $args{delimiter} ? $args{delimiter} : "\t";
    my $encoding           = $args{encoding} // 'UTF-8';
    my $line_ending        = exists $args{line_ending} ? $args{line_ending} : "\n";
    my $sanitize_newlines  = exists $args{sanitize_newlines} ? $args{sanitize_newlines} : 1;
    my $undef_value        = exists $args{undef_value} ? $args{undef_value} : '';
    my $quote_fields       = $args{quote_fields} ? 1 : 0;

    die "write_delimited_file: 'path' is required\n" unless defined $path && $path ne '';
    die "write_delimited_file: 'rows' must be an arrayref\n" unless ref($rows) eq 'ARRAY';
    die "write_delimited_file: 'columns' must be an arrayref when provided\n"
        if defined $columns && ref($columns) ne 'ARRAY';
    die "write_delimited_file: 'delimiter' must be defined\n" unless defined $delimiter;

    _require_parent_directory($path);

    open my $fh, '>:raw', $path or die "Cannot open file '$path' for writing: $!\n";

    if (defined $columns) {
        my $header = _format_delimited_row(
            values             => $columns,
            delimiter          => $delimiter,
            sanitize_newlines  => $sanitize_newlines,
            undef_value        => $undef_value,
            quote_fields       => $quote_fields,
        );
        print {$fh} encode($encoding, $header . $line_ending);
    }

    for my $row (@$rows) {
        die "write_delimited_file: each row must be an arrayref\n" unless ref($row) eq 'ARRAY';

        my $line = _format_delimited_row(
            values             => $row,
            delimiter          => $delimiter,
            sanitize_newlines  => $sanitize_newlines,
            undef_value        => $undef_value,
            quote_fields       => $quote_fields,
        );

        print {$fh} encode($encoding, $line . $line_ending);
    }

    close $fh;
    return $path;
}

sub _write_text_file {
    my (%args) = @_;

    my $path      = $args{path};
    my $content   = $args{content};
    my $encoding  = $args{encoding} // 'UTF-8';
    my $append    = $args{append} ? 1 : 0;

    die "_write_text_file: 'path' is required\n" unless defined $path && $path ne '';
    die "_write_text_file: 'content' is required\n" unless defined $content;

    _require_parent_directory($path);

    my $mode = $append ? '>>:raw' : '>:raw';
    open my $fh, $mode, $path or die "Cannot open file '$path' for writing: $!\n";
    print {$fh} encode($encoding, $content);
    close $fh;

    return $path;
}

sub _require_parent_directory {
    my ($path) = @_;
    my $directory = dirname($path);
    die "Parent directory not found for file '$path'\n" unless -d $directory;
}

sub _format_delimited_row {
    my (%args) = @_;

    my $values              = $args{values};
    my $delimiter           = $args{delimiter};
    my $sanitize_newlines   = $args{sanitize_newlines};
    my $undef_value         = $args{undef_value};
    my $quote_fields        = $args{quote_fields};

    my @formatted = map {
        my $value = defined $_ ? "$_" : $undef_value;
        $value =~ s/[\r\n]+/ /g if $sanitize_newlines;

        if ($quote_fields && ($value =~ /\Q$delimiter\E/ || $value =~ /"/ || $value =~ /[\r\n]/)) {
            $value =~ s/"/""/g;
            $value = qq{"$value"};
        }

        $value;
    } @$values;

    return join($delimiter, @formatted);
}

1;
