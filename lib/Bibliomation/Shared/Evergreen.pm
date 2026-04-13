package Bibliomation::Shared::Evergreen;

use strict;
use warnings;
use XML::Simple;
use Exporter 'import';

our @EXPORT_OK = qw(get_database_configuration);

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

1;
