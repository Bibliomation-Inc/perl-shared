package Bibliomation::Shared::Evergreen;

use strict;
use warnings;
use XML::Simple;
use Exporter 'import';

our @EXPORT_OK = qw(get_database_configuration get_org_units);

sub get_database_configuration {
    my ($config_file) = @_;
    $config_file ||= '/openils/conf/opensrf.xml';

    die "Configuration file not found: $config_file\n" unless -e $config_file;

    my $xml = XML::Simple->new(ForceArray => 0, KeyAttr => []);
    my $config = $xml->XMLin($config_file);

    my $db_section = _find_database_section($config);
    die "Could not find database configuration in opensrf.xml\n" unless $db_section;

    my @required = qw(host port db user pw);
    for my $key (@required) {
        die "Missing required database config key: $key\n" unless defined $db_section->{$key};
    }

    return {
        host     => $db_section->{host},
        port     => 0 + $db_section->{port},
        name     => $db_section->{db},
        user     => $db_section->{user},
        password => $db_section->{pw},
    };
}

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

    die "No organization units found for library shortnames: $librarynames\n" unless @org_unit_ids;
    return _dedupe_sorted(\@org_unit_ids);
}

sub _find_database_section {
    my ($config) = @_;

    if ($config->{default} && 
        $config->{default}{apps} && 
        $config->{default}{apps}{'open-ils.cstore'} &&
        $config->{default}{apps}{'open-ils.cstore'}{app_settings} &&
        $config->{default}{apps}{'open-ils.cstore'}{app_settings}{database}) {
        return $config->{default}{apps}{'open-ils.cstore'}{app_settings}{database};
    }

    if ($config->{default} && 
        $config->{default}{apps} && 
        $config->{default}{apps}{'open-ils.storage'} &&
        $config->{default}{apps}{'open-ils.storage'}{app_settings} &&
        $config->{default}{apps}{'open-ils.storage'}{app_settings}{databases} &&
        $config->{default}{apps}{'open-ils.storage'}{app_settings}{databases}{database}) {
        return $config->{default}{apps}{'open-ils.storage'}{app_settings}{databases}{database};
    }

    if ($config->{default} && 
        $config->{default}{reporter} && 
        $config->{default}{reporter}{setup} &&
        $config->{default}{reporter}{setup}{database}) {
        return $config->{default}{reporter}{setup}{database};
    }
    
    return undef;
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
