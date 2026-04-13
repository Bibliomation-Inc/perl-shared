requires 'DBI';
requires 'Email::MIME';
requires 'Email::Sender::Simple';
requires 'Net::SFTP::Foreign';
requires 'Try::Tiny';

on test => sub {
    requires 'Test::More';
};
