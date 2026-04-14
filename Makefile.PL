use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'Bibliomation::Shared',
    VERSION      => '0.006',
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
    test         => { TESTS => 't/*.t' },
);
