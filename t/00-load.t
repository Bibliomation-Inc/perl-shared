use strict;
use warnings;
use Test::More;

use_ok('Bibliomation::Shared::ArrayUtils');
use_ok('Bibliomation::Shared::ConfigFile');
use_ok('Bibliomation::Shared::Database');
use_ok('Bibliomation::Shared::Email');
use_ok('Bibliomation::Shared::Logging');

my $has_sftp_dep = eval {
	require Net::SFTP::Foreign;
	1;
};

if ($has_sftp_dep) {
	use_ok('Bibliomation::Shared::SFTP');
} else {
	pass('Skipping SFTP module load check: Net::SFTP::Foreign not installed');
}

done_testing();
