use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'Bibliomation::Shared',
    VERSION      => '0.003',
    ABSTRACT     => 'Shared Perl utility modules',
    AUTHOR       => 'Bibliomation',
    LICENSE      => 'perl',
    PREREQ_PM    => {
        'Archive::Tar'          => 0,
        'DBD::Pg'               => 0,
        'DBI'                   => 0,
        'Email::MIME'           => 0,
        'Email::Sender::Simple' => 0,
        'Net::SFTP::Foreign'    => 0,
        'XML::Simple'           => 0,
        'Test::More'            => 0,
    },
    PM           => {
        'lib/Bibliomation/Shared/Archive.pm'    => '$(INST_LIBDIR)/Archive.pm',
        'lib/Bibliomation/Shared/ArrayUtils.pm' => '$(INST_LIBDIR)/ArrayUtils.pm',
        'lib/Bibliomation/Shared/ConfigFile.pm' => '$(INST_LIBDIR)/ConfigFile.pm',
        'lib/Bibliomation/Shared/Database.pm'   => '$(INST_LIBDIR)/Database.pm',
        'lib/Bibliomation/Shared/Email.pm'      => '$(INST_LIBDIR)/Email.pm',
        'lib/Bibliomation/Shared/Evergreen.pm'  => '$(INST_LIBDIR)/Evergreen.pm',
        'lib/Bibliomation/Shared/FileIO.pm'     => '$(INST_LIBDIR)/FileIO.pm',
        'lib/Bibliomation/Shared/Logging.pm'    => '$(INST_LIBDIR)/Logging.pm',
        'lib/Bibliomation/Shared/SFTP.pm'       => '$(INST_LIBDIR)/SFTP.pm',
    },
    test         => { TESTS => 't/*.t' },
);
