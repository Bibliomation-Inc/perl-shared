requires 'DBI';
requires 'Email::MIME';
requires 'Email::Sender::Simple';
requires 'Net::SFTP::Foreign';
requires 'XML::Simple';

on test => sub {
    requires 'Test::More';
};
