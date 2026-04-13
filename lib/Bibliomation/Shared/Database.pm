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

sub setup_database_connection {
    my ($db_config) = @_;

    die "setup_database_connection: database configuration hashref is required\n"
        unless ref($db_config) eq 'HASH';

    for my $key (qw(name host port user password)) {
        die "setup_database_connection: missing required config key '$key'\n"
            unless defined $db_config->{$key} && $db_config->{$key} ne '';
    }

    my $dsn = sprintf(
        'DBI:Pg:dbname=%s;host=%s;port=%s',
        $db_config->{name},
        $db_config->{host},
        $db_config->{port},
    );

    $database_handle = DBI->connect(
        $dsn,
        $db_config->{user},
        $db_config->{password},
        {
            RaiseError    => 1,
            PrintError    => 0,
            AutoCommit    => 1,
            pg_enable_utf8 => 1,
        },
    );

    return $database_handle;
}

sub run_sql {
    my ($sql, @params) = @_;

    my $dbh = _require_database_handle();
    die "No SQL provided\n" unless defined $sql && $sql =~ /\S/;

    my $sth = $dbh->prepare($sql);
    $sth->execute(@params);

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

    my $sql = _load_sql_file($file_path);
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
    die "stream_id_chunks: 'bind_params' must be an arrayref\n" unless ref($bind_params) eq 'ARRAY';
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
    die "run_query_for_ids: 'bind_params' must be an arrayref\n" unless ref($bind_params) eq 'ARRAY';
    die "run_query_for_ids: 'list_token' must be non-empty\n" unless defined $list_token && $list_token ne '';
    return [] unless @$id_values;

    my $occurrences = () = $query =~ /\Q$list_token\E/g;
    die "run_query_for_ids: list token '$list_token' not found in query\n" unless $occurrences > 0;

    my $placeholders = join(',', ('?') x scalar(@$id_values));
    my $sql = $query;
    $sql =~ s/\Q$list_token\E/$placeholders/g;

    my @all_bind_params = _build_bind_params(
        original_query => $query,
        list_token     => $list_token,
        id_values      => $id_values,
        bind_params    => $bind_params,
    );

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

    my $id_sql             = $args{id_sql};
    my $id_bind_params     = $args{id_bind_params} || [];
    my $detail_sql         = $args{detail_sql};
    my $detail_bind_params = $args{detail_bind_params} || [];
    my $list_token         = $args{list_token} // ':id_list';
    my $chunk_size         = $args{chunk_size} || 500;
    my $on_chunk_rows      = $args{on_chunk_rows};

    _require_database_handle();

    die "run_chunked_id_query: 'id_sql' is required\n" unless defined $id_sql && $id_sql =~ /\S/;
    die "run_chunked_id_query: 'detail_sql' is required\n" unless defined $detail_sql && $detail_sql =~ /\S/;
    die "run_chunked_id_query: 'id_bind_params' must be an arrayref\n" unless ref($id_bind_params) eq 'ARRAY';
    die "run_chunked_id_query: 'detail_bind_params' must be an arrayref\n" unless ref($detail_bind_params) eq 'ARRAY';
    die "run_chunked_id_query: 'on_chunk_rows' must be a coderef when provided\n"
        if defined $on_chunk_rows && ref($on_chunk_rows) ne 'CODE';

    my @all_rows;

    stream_id_chunks(
        id_sql      => $id_sql,
        bind_params => $id_bind_params,
        chunk_size  => $chunk_size,
        on_chunk    => sub {
            my ($id_chunk) = @_;
            my $rows = run_query_for_ids(
                id_values   => $id_chunk,
                list_token  => $list_token,
                query       => $detail_sql,
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
    die "No SQL provided\n" unless defined $sql && $sql =~ /\S/;
    return $dbh->prepare($sql);
}

sub execute_prepared {
    my ($sth, @params) = @_;
    die "execute_prepared: statement handle is required\n" unless defined $sth;
    return $sth->execute(@params);
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

sub _require_database_handle {
    die "No database connection established\n" unless defined $database_handle;
    return $database_handle;
}

sub _load_sql_file {
    my ($file_path) = @_;

    die "No SQL file path provided\n" unless defined $file_path;
    die "SQL file not found: $file_path\n" unless -e $file_path;

    open my $fh, '<', $file_path or die "Cannot open SQL file '$file_path': $!\n";
    my $sql = do { local $/; <$fh> };
    close $fh;

    $sql =~ s{/\*.*?\*/}{}gs;
    $sql =~ s/^\s*--.*$//mg;
    $sql =~ s/^\s*(?:BEGIN|COMMIT|ROLLBACK)\s*;\s*$//img;
    $sql =~ s/^\s+//;
    $sql =~ s/\s+$//;
    $sql =~ s/;\s*$//;

    die "SQL file '$file_path' did not contain executable SQL\n" unless $sql =~ /\S/;
    return $sql;
}

sub _build_bind_params {
    my (%args) = @_;

    my $original_query = $args{original_query};
    my $list_token     = $args{list_token};
    my $id_values      = $args{id_values};
    my $bind_params    = $args{bind_params};

    my @final_params;
    my $bind_index = 0;

    while ($original_query =~ /(\Q$list_token\E|\?)/g) {
        if ($1 eq '?') {
            die "run_query_for_ids: missing bind parameter for placeholder\n"
                if $bind_index >= @$bind_params;
            push @final_params, $bind_params->[$bind_index++];
        } else {
            push @final_params, @$id_values;
        }
    }

    die "run_query_for_ids: too many bind parameters supplied\n" if $bind_index != @$bind_params;
    return @final_params;
}

1;
