use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);

use Bibliomation::Shared::Evergreen qw(get_database_configuration);

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

done_testing();
