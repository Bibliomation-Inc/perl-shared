use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'Bibliomation::Shared',
    VERSION      => '0.001',
    ABSTRACT     => 'Shared Perl modules for Bibliomation projects',
    AUTHOR       => 'Bibliomation',
    LICENSE      => 'perl',
    PREREQ_PM    => {
        'DBI'                   => 0,
        'Email::MIME'           => 0,
        'Email::Sender::Simple' => 0,
        'Net::SFTP::Foreign'    => 0,
        'Try::Tiny'             => 0,
        'Test::More'            => 0,
    },
    PM           => {
        'lib/Bibliomation/Shared/ConfigFile.pm' => '$(INST_LIBDIR)/ConfigFile.pm',
        'lib/Bibliomation/Shared/Database.pm'   => '$(INST_LIBDIR)/Database.pm',
        'lib/Bibliomation/Shared/Email.pm'      => '$(INST_LIBDIR)/Email.pm',
        'lib/Bibliomation/Shared/Logging.pm'    => '$(INST_LIBDIR)/Logging.pm',
        'lib/Bibliomation/Shared/SFTP.pm'       => '$(INST_LIBDIR)/SFTP.pm',
    },
    test         => { TESTS => 't/*.t' },
);
