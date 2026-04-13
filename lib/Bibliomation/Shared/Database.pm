package Bibliomation::Shared::Database;

use strict;
use warnings;
use DBI;
use Exporter 'import';

our @EXPORT_OK = qw(
    setup_database_connection
    run_sql
    run_sql_file
    stream_id_chunks
    run_query_for_ids
    run_chunked_id_query
    prepare_sql
    execute_prepared
    begin_transaction
    commit_transaction
    rollback_transaction
);

my $database_handle;

sub _require_database_handle {
    die "No database connection established\n" unless defined $database_handle;
    return $database_handle;
}

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

    my $dbh = _require_database_handle();
    die "No SQL provided\n" unless defined $sql && $sql =~ /\S/;

    my $sth = $dbh->prepare($sql);
    $sth->execute(@params);

    # NUM_OF_FIELDS is > 0 for statements that return a result set.
    my $has_result_set = ($sth->{NUM_OF_FIELDS} && $sth->{NUM_OF_FIELDS} > 0) ? 1 : 0;

    if ($has_result_set) {
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

    return run_sql($sql, @params);
}

sub stream_id_chunks {
    my (%args) = @_;

    my $dbh         = _require_database_handle();
    my $id_sql      = $args{id_sql};
    my $bind_params = $args{bind_params} || [];
    my $chunk_size  = $args{chunk_size} || 1000;
    my $on_chunk    = $args{on_chunk};

    die "stream_id_chunks: 'id_sql' is required\n" unless defined $id_sql && $id_sql =~ /\S/;
    die "stream_id_chunks: 'on_chunk' callback is required\n" unless ref($on_chunk) eq 'CODE';
    die "stream_id_chunks: 'chunk_size' must be > 0\n" unless $chunk_size > 0;

    my $sth = $dbh->prepare($id_sql);
    $sth->execute(@$bind_params);

    my @chunk;
    while (my ($id) = $sth->fetchrow_array) {
        push @chunk, $id;
        if (@chunk >= $chunk_size) {
            $on_chunk->(\@chunk);
            @chunk = ();
        }
    }

    $on_chunk->(\@chunk) if @chunk;
    $sth->finish;

    return 1;
}

sub run_query_for_ids {
    my (%args) = @_;

    my $dbh         = _require_database_handle();
    my $id_values   = $args{id_values} || [];
    my $query       = $args{query};
    my $list_token  = $args{list_token} // ':id_list';
    my $bind_params = $args{bind_params} || [];

    die "run_query_for_ids: 'query' is required\n" unless defined $query && $query =~ /\S/;
    die "run_query_for_ids: 'id_values' must be an arrayref\n" unless ref($id_values) eq 'ARRAY';
    die "run_query_for_ids: 'list_token' must be non-empty\n" unless defined $list_token && $list_token ne '';
    return [] unless @$id_values;

    my $occurrences = () = $query =~ /\Q$list_token\E/g;
    die "run_query_for_ids: list token '$list_token' not found in query\n" unless $occurrences > 0;
    my $ids_in_chunk = scalar @$id_values;

    my $placeholders = join(',', ('?') x $ids_in_chunk);
    my $sql = $query;
    $sql =~ s/\Q$list_token\E/$placeholders/g;

    my @bind_ids;
    if ($occurrences > 1) {
        for (1 .. $occurrences) {
            push @bind_ids, @$id_values;
        }
    } else {
        @bind_ids = @$id_values;
    }

    my @all_bind_params = (@bind_ids, @$bind_params);

    my $sth = $dbh->prepare($sql);
    $sth->execute(@all_bind_params);

    my @rows;
    while (my $row = $sth->fetchrow_arrayref) {
        push @rows, [@$row];
    }
    $sth->finish;

    return \@rows;
}

sub run_chunked_id_query {
    my (%args) = @_;

    my $id_sql       = $args{id_sql};
    my $id_bind_params = $args{id_bind_params} || [];
    my $detail_sql   = $args{detail_sql};
    my $detail_bind_params = $args{detail_bind_params} || [];
    my $list_token   = $args{list_token} // ':id_list';
    my $chunk_size   = $args{chunk_size} || 500;
    my $on_chunk_rows = $args{on_chunk_rows};

    _require_database_handle();
    die "run_chunked_in_query: 'id_sql' is required\n" unless defined $id_sql && $id_sql =~ /\S/;
    die "run_chunked_in_query: 'detail_sql' is required\n" unless defined $detail_sql && $detail_sql =~ /\S/;

    my @all_rows;

    stream_id_chunks(
        id_sql => $id_sql,
        bind_params => $id_bind_params,
        chunk_size => $chunk_size,
        on_chunk => sub {
            my ($id_chunk) = @_;
            my $rows = run_query_for_ids(
                id_values => $id_chunk,
                list_token => $list_token,
            query => $detail_sql,
                bind_params => $detail_bind_params,
            );

            if (ref($on_chunk_rows) eq 'CODE') {
                $on_chunk_rows->($rows, $id_chunk);
            } else {
                push @all_rows, @$rows;
            }
        },
    );

    return ref($on_chunk_rows) eq 'CODE' ? 1 : \@all_rows;
}

sub prepare_sql {
    my ($sql) = @_;
    my $dbh = _require_database_handle();
    return $dbh->prepare($sql);
}

sub execute_prepared {
    my ($sth, @params) = @_;
    $sth->execute(@params);
}

sub begin_transaction {
    my $dbh = _require_database_handle();
    $dbh->{AutoCommit} = 0;
}

sub commit_transaction {
    my $dbh = _require_database_handle();
    $dbh->commit();
    $dbh->{AutoCommit} = 1;
}

sub rollback_transaction {
    my $dbh = _require_database_handle();
    $dbh->rollback();
    $dbh->{AutoCommit} = 1;
}

1;
