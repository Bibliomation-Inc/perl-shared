use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);

use Bibliomation::Shared::Evergreen qw(get_database_configuration get_org_units);

sub exception (&) {
    my $code = shift;
    eval { $code->(); 1 };
    return $@;
}

my ($cstore_fh, $cstore_path) = tempfile();
print {$cstore_fh} <<'XML';
<config>
  <default>
    <apps>
      <open-ils.cstore>
        <app_settings>
          <database>
            <host>db.example.org</host>
            <port>5432</port>
            <db>evergreen</db>
            <user>eg_user</user>
            <pw>eg_pass</pw>
          </database>
        </app_settings>
      </open-ils.cstore>
    </apps>
  </default>
</config>
XML
close $cstore_fh;

my $cstore_config = get_database_configuration($cstore_path);
is_deeply(
    $cstore_config,
    {
        host     => 'db.example.org',
        port     => 5432,
        name     => 'evergreen',
        user     => 'eg_user',
        password => 'eg_pass',
    },
    'get_database_configuration normalizes cstore settings',
);

my ($storage_fh, $storage_path) = tempfile();
print {$storage_fh} <<'XML';
<config>
  <default>
    <apps>
      <open-ils.storage>
        <app_settings>
          <databases>
            <database>
              <host>storage.example.org</host>
              <port>5444</port>
              <db>evergreen_storage</db>
              <user>storage_user</user>
              <pw>storage_pass</pw>
            </database>
          </databases>
        </app_settings>
      </open-ils.storage>
    </apps>
  </default>
</config>
XML
close $storage_fh;

my $storage_config = get_database_configuration($storage_path);
is($storage_config->{name}, 'evergreen_storage', 'falls back to open-ils.storage when cstore is absent');
is($storage_config->{password}, 'storage_pass', 'maps pw to password in fallback config');

like(
    exception { get_database_configuration('definitely_missing_opensrf.xml') },
    qr/Configuration file not found/,
    'dies on missing Evergreen config file',
);

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
