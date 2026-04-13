package Bibliomation::Shared::Database;

use strict;
use warnings;
use DBI;
use Exporter 'import';

our @EXPORT_OK = qw(
    setup_database_connection
    run_sql
    run_sql_file
    prepare_sql
    execute_prepared
    begin_transaction
    commit_transaction
    rollback_transaction
);

my $database_handle;

sub setup_database_connection {
    my ($db_config) = @_;

    my $dsn = "DBI:Pg:dbname=$db_config->{name};host=$db_config->{host};port=$db_config->{port}";
    $database_handle = DBI->connect(
        $dsn,
        $db_config->{user},
        $db_config->{password},
        { RaiseError => 1, AutoCommit => 1, pg_enable_utf8 => 1 }
    );

    return $database_handle;
}

sub run_sql {
    my ($sql, @params) = @_;

    die "No database connection established\n" unless defined $database_handle;
    die "No SQL provided\n" unless defined $sql && $sql =~ /\S/;

    my $sth = $database_handle->prepare($sql);
    $sth->execute(@params);

    my $is_select = ($sql =~ /\bSELECT\b/i && $sql !~ /\b(INSERT|UPDATE|DELETE|CREATE|DROP|ALTER)\b/i);

    if ($is_select) {
        my $results = $sth->fetchall_arrayref({});
        $sth->finish();
        return $results;
    }

    my $rows = $sth->rows;
    $sth->finish();
    return $rows;
}

sub run_sql_file {
    my ($file_path, @params) = @_;

    die "No SQL file path provided\n" unless defined $file_path;
    die "SQL file not found: $file_path\n" unless -e $file_path;

    open my $fh, '<', $file_path or die "Cannot open SQL file '$file_path': $!\n";
    my $sql = do { local $/; <$fh> };
    close $fh;

    $sql =~ s/^\s*BEGIN\s*;\s*$//im;
    $sql =~ s/^\s*(COMMIT|ROLLBACK)\s*;\s*$//im;
    $sql =~ s/--.*$//mg;
    $sql =~ s{/\*.*?\*/}{}gs;
    $sql =~ s/^\s+//;
    $sql =~ s/\s+$//;

    return run_sql($sql, @params);
}

sub prepare_sql {
    my ($sql) = @_;
    die "No database connection established\n" unless defined $database_handle;
    return $database_handle->prepare($sql);
}

sub execute_prepared {
    my ($sth, @params) = @_;
    $sth->execute(@params);
}

sub begin_transaction {
    die "No database connection established\n" unless defined $database_handle;
    $database_handle->{AutoCommit} = 0;
}

sub commit_transaction {
    die "No database connection established\n" unless defined $database_handle;
    $database_handle->commit();
    $database_handle->{AutoCommit} = 1;
}

sub rollback_transaction {
    die "No database connection established\n" unless defined $database_handle;
    $database_handle->rollback();
    $database_handle->{AutoCommit} = 1;
}

1;
