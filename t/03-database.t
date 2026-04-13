use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);

use Bibliomation::Shared::Database qw(
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

sub exception (&) {
    my $code = shift;
    eval { $code->(); 1 };
    return $@;
}

{
    my $err = exception { run_sql('SELECT 1') };
    like($err, qr/No database connection established/, 'run_sql requires connection');
}

my $dbh = MockDBH->new();
install_mock_connect($dbh);

my $connected = setup_database_connection({
    name => 'db',
    host => 'localhost',
    port => 5432,
    user => 'u',
    password => 'p',
});
is($connected, $dbh, 'setup_database_connection stores and returns handle');

$dbh->queue_prepare(sub {
    my ($self, $sql) = @_;
    like($sql, qr/SELECT\s+id\s+FROM\s+users/i, 'run_sql prepares SELECT');
    return MockSTH->select_hash_rows([
        { id => 1, name => 'Alice' },
        { id => 2, name => 'Bob' },
    ]);
});

my $select_rows = run_sql('SELECT id FROM users WHERE active = ?', 1);
is_deeply($select_rows, [{ id => 1, name => 'Alice' }, { id => 2, name => 'Bob' }], 'run_sql returns hash rows for result-set queries');

$dbh->queue_prepare(sub {
    my ($self, $sql) = @_;
    like($sql, qr/UPDATE\s+users/i, 'run_sql prepares non-select');
    return MockSTH->non_select_rows(3);
});

my $affected = run_sql('UPDATE users SET active = ? WHERE id > ?', 0, 100);
is($affected, 3, 'run_sql returns row count for non-result statements');

my ($sql_fh, $sql_path) = tempfile();
print {$sql_fh} "SELECT id FROM source WHERE group_id = ?\n";
close $sql_fh;

$dbh->queue_prepare(sub {
    my ($self, $sql) = @_;
    like($sql, qr/SELECT\s+id\s+FROM\s+source/i, 'run_sql_file loads SQL from file');
    return MockSTH->select_hash_rows([{ id => 9 }]);
});

my $file_rows = run_sql_file($sql_path, 42);
is_deeply($file_rows, [{ id => 9 }], 'run_sql_file executes loaded SQL');

$dbh->queue_prepare(sub {
    my ($self, $sql) = @_;
    like($sql, qr/source_ids/, 'stream_id_chunks prepares ID query');
    return MockSTH->id_stream([1, 2, 3, 4, 5]);
});

my @id_chunks;
my $stream_result = stream_id_chunks(
    id_sql => 'SELECT id FROM source_ids WHERE ts > ?',
    bind_params => ['2025-01-01'],
    chunk_size => 2,
    on_chunk => sub {
        my ($chunk) = @_;
        push @id_chunks, [@$chunk];
    },
);
ok($stream_result, 'stream_id_chunks returns success value');
is_deeply(\@id_chunks, [[1, 2], [3, 4], [5]], 'stream_id_chunks emits expected chunk boundaries');

$dbh->queue_prepare(sub {
    my ($self, $sql) = @_;
    like($sql, qr/IN\s*\(\?,\?,\?\)/, 'run_query_for_ids expands token into placeholders');
    return MockSTH->array_rows_from_execute(sub {
        my (@bind) = @_;
        is_deeply(\@bind, [10, 20, 30, 99], 'run_query_for_ids binds ids then additional params');
        return [
            [10, 'a'],
            [20, 'b'],
            [30, 'c'],
        ];
    });
});

my $detail_rows = run_query_for_ids(
    query => 'SELECT id, val FROM detail WHERE id IN (:id_list) AND flag = ?',
    id_values => [10, 20, 30],
    bind_params => [99],
);

is_deeply($detail_rows, [[10, 'a'], [20, 'b'], [30, 'c']], 'run_query_for_ids returns array rows');

$dbh->queue_prepare(sub {
    my ($self, $sql) = @_;
    like($sql, qr/FROM\s+big_source/i, 'run_chunked_id_query prepares source id SQL');
    return MockSTH->id_stream([101, 102, 103, 104, 105]);
});

$dbh->queue_prepare(sub {
    my ($self, $sql) = @_;
    like($sql, qr/IN\s*\(\?,\?\)/, 'chunk 1 detail SQL has two placeholders');
    return MockSTH->array_rows_from_execute(sub {
        my (@bind) = @_;
        return [[ $bind[0], 'r' . $bind[0] ], [ $bind[1], 'r' . $bind[1] ]];
    });
});

$dbh->queue_prepare(sub {
    my ($self, $sql) = @_;
    like($sql, qr/IN\s*\(\?,\?\)/, 'chunk 2 detail SQL has two placeholders');
    return MockSTH->array_rows_from_execute(sub {
        my (@bind) = @_;
        return [[ $bind[0], 'r' . $bind[0] ], [ $bind[1], 'r' . $bind[1] ]];
    });
});

$dbh->queue_prepare(sub {
    my ($self, $sql) = @_;
    like($sql, qr/IN\s*\(\?\)/, 'chunk 3 detail SQL has one placeholder');
    return MockSTH->array_rows_from_execute(sub {
        my (@bind) = @_;
        return [[ $bind[0], 'r' . $bind[0] ]];
    });
});

my $chunked_rows = run_chunked_id_query(
    id_sql => 'SELECT id FROM big_source',
    detail_sql => 'SELECT id, payload FROM detail WHERE id IN (:id_list)',
    chunk_size => 2,
);

is_deeply(
    $chunked_rows,
    [[101, 'r101'], [102, 'r102'], [103, 'r103'], [104, 'r104'], [105, 'r105']],
    'run_chunked_id_query aggregates rows from all chunks'
);

$dbh->queue_prepare(sub {
    my ($self, $sql) = @_;
    like($sql, qr/SELECT\s+now\(\)/i, 'prepare_sql forwards SQL text to DBI prepare');
    return MockSTH->non_select_rows(0);
});

my $prepared_sth = prepare_sql('SELECT now()');
ok($prepared_sth, 'prepare_sql returns statement handle');
execute_prepared($prepared_sth, 1, 2, 3);
is_deeply($prepared_sth->{last_execute_params}, [1, 2, 3], 'execute_prepared forwards bind params');

begin_transaction();
ok(!$dbh->{AutoCommit}, 'begin_transaction disables AutoCommit');
commit_transaction();
ok($dbh->{AutoCommit}, 'commit_transaction re-enables AutoCommit');

begin_transaction();
rollback_transaction();
ok($dbh->{AutoCommit}, 'rollback_transaction re-enables AutoCommit');

ok(!@{$dbh->{prepare_handlers}}, 'all queued prepare handlers were consumed');

done_testing();

sub install_mock_connect {
    my ($mock_dbh) = @_;
    no warnings 'redefine';
    *DBI::connect = sub {
        return $mock_dbh;
    };
}

{
    package MockDBH;

    sub new {
        my ($class) = @_;
        return bless {
            prepare_handlers => [],
            AutoCommit => 1,
        }, $class;
    }

    sub queue_prepare {
        my ($self, $handler) = @_;
        push @{$self->{prepare_handlers}}, $handler;
    }

    sub prepare {
        my ($self, $sql) = @_;
        my $handler = shift @{$self->{prepare_handlers}};
        die "No queued prepare handler for SQL: $sql" unless $handler;
        return $handler->($self, $sql);
    }

    sub commit {
        my ($self) = @_;
        $self->{committed}++;
    }

    sub rollback {
        my ($self) = @_;
        $self->{rolled_back}++;
    }
}

{
    package MockSTH;

    sub select_hash_rows {
        my ($class, $rows) = @_;
        return bless {
            NUM_OF_FIELDS => 1,
            hash_rows => $rows,
        }, $class;
    }

    sub non_select_rows {
        my ($class, $rows) = @_;
        return bless {
            NUM_OF_FIELDS => 0,
            rows_affected => $rows,
        }, $class;
    }

    sub id_stream {
        my ($class, $ids) = @_;
        return bless {
            NUM_OF_FIELDS => 1,
            ids => [@$ids],
            id_index => 0,
        }, $class;
    }

    sub array_rows_from_execute {
        my ($class, $builder) = @_;
        return bless {
            NUM_OF_FIELDS => 1,
            builder => $builder,
            array_rows => undef,
            row_index => 0,
        }, $class;
    }

    sub execute {
        my ($self, @params) = @_;
        $self->{last_execute_params} = [@params];

        if ($self->{builder}) {
            my $rows = $self->{builder}->(@params);
            $self->{array_rows} = $rows;
            $self->{row_index} = 0;
        }

        return 1;
    }

    sub fetchall_arrayref {
        my ($self, $slice) = @_;
        return $self->{hash_rows} || [];
    }

    sub rows {
        my ($self) = @_;
        return $self->{rows_affected} // 0;
    }

    sub fetchrow_array {
        my ($self) = @_;
        return if !defined $self->{ids};
        return if $self->{id_index} >= @{$self->{ids}};
        my $id = $self->{ids}->[$self->{id_index}++];
        return ($id);
    }

    sub fetchrow_arrayref {
        my ($self) = @_;
        my $rows = $self->{array_rows} || [];
        return if $self->{row_index} >= @$rows;
        return $rows->[$self->{row_index}++];
    }

    sub finish {
        return 1;
    }
}
