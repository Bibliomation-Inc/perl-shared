package Bibliomation::Shared::ArrayUtils;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(dedupe_array);

sub dedupe_array {
    my ($arr_ref) = @_;
    my @arr = $arr_ref ? @{$arr_ref} : ();

    my %seen;
    $seen{$_} = 1 for @arr;

    my @deduped = sort keys %seen;
    return \@deduped;
}

1;
