package Bibliomation::Shared::EvergreenOrgUnits;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(get_org_units);

sub get_org_units {
    my ($dbh, $librarynames, $include_descendants) = @_;

    die "get_org_units: database handle is required\n" unless defined $dbh;

    $librarynames //= '';
    $librarynames =~ s/\s//g;

    my @shortnames = grep { $_ ne '' } map { lc $_ } split(/,/, $librarynames);
    die "No library shortnames provided\n" unless @shortnames;

    my $placeholders = join(',', ('?') x @shortnames);
    my $query = qq{
        SELECT id
        FROM actor.org_unit
        WHERE lower(shortname) IN ($placeholders)
        ORDER BY 1
    };

    my @org_unit_ids;
    my $sth = $dbh->prepare($query);
    $sth->execute(@shortnames);

    while (my ($id) = $sth->fetchrow_array) {
        push @org_unit_ids, $id;
        if ($include_descendants) {
            push @org_unit_ids, @{ _get_org_descendants($dbh, $id) };
        }
    }

    $sth->finish;

    if (!@org_unit_ids) {
        die "No organization units found for library shortnames: $librarynames\n";
    }

    return _dedupe_sorted(\@org_unit_ids);
}

sub _get_org_descendants {
    my ($dbh, $org_unit_id) = @_;

    my $query = 'SELECT id FROM actor.org_unit_descendants(?)';
    my @descendant_ids;
    my $sth = $dbh->prepare($query);
    $sth->execute($org_unit_id);

    while (my ($id) = $sth->fetchrow_array) {
        push @descendant_ids, $id;
    }

    $sth->finish;
    return \@descendant_ids;
}

sub _dedupe_sorted {
    my ($arr_ref) = @_;
    my @values = $arr_ref ? @{$arr_ref} : ();

    my %seen;
    $seen{$_} = 1 for @values;

    return [sort keys %seen];
}

1;
