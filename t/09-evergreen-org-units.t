use strict;
use warnings;
use Test::More;

use Bibliomation::Shared::EvergreenOrgUnits qw(get_org_units);

sub exception (&) {
    my $code = shift;
    eval { $code->(); 1 };
    return $@;
}

{
    my $dbh = MockDBH->new();

    $dbh->queue_prepare(sub {
        my ($self, $sql) = @_;
        like($sql, qr/lower\(shortname\)\s+IN\s+\(\?,\?\)/i, 'get_org_units prepares placeholder query');
        return MockSTH->rows([[12], [34]]);
    });

    my $org_units = get_org_units($dbh, ' BR1 , BR2 ', 0);
    is_deeply($org_units, [12, 34], 'get_org_units returns matching org units without descendants');
}

{
    my $dbh = MockDBH->new();

    $dbh->queue_prepare(sub {
        my ($self, $sql) = @_;
        return MockSTH->rows([[34], [12]]);
    });

    $dbh->queue_prepare(sub {
        my ($self, $sql) = @_;
        like($sql, qr/org_unit_descendants/i, 'descendant query is prepared for first match');
        return MockSTH->rows([[50], [51]]);
    });

    $dbh->queue_prepare(sub {
        my ($self, $sql) = @_;
        like($sql, qr/org_unit_descendants/i, 'descendant query is prepared for second match');
        return MockSTH->rows([[51], [60]]);
    });

    my $org_units = get_org_units($dbh, 'BR2,BR1', 1);
    is_deeply($org_units, [12, 34, 50, 51, 60], 'get_org_units includes descendants, dedupes, and sorts');
}

{
    my $dbh = MockDBH->new();
    my $err = exception { get_org_units($dbh, '', 0) };
    like($err, qr/No library shortnames provided/, 'get_org_units requires at least one shortname');
}

{
    my $dbh = MockDBH->new();

    $dbh->queue_prepare(sub {
        my ($self, $sql) = @_;
        return MockSTH->rows([]);
    });

    my $err = exception { get_org_units($dbh, 'BR1', 0) };
    like($err, qr/No organization units found/, 'get_org_units dies when no org units match');
}

done_testing();

{
    package MockDBH;

    sub new {
        my ($class) = @_;
        return bless {
            prepare_handlers => [],
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
}

{
    package MockSTH;

    sub rows {
        my ($class, $rows) = @_;
        return bless {
            rows => $rows,
            row_index => 0,
        }, $class;
    }

    sub execute {
        my ($self, @params) = @_;
        $self->{last_execute_params} = [@params];
        return 1;
    }

    sub fetchrow_array {
        my ($self) = @_;
        return if $self->{row_index} >= @{$self->{rows}};
        my $row = $self->{rows}->[$self->{row_index}++];
        return @$row;
    }

    sub finish {
        return 1;
    }
}
