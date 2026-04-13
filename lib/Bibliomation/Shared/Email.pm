package Bibliomation::Shared::Email;

use strict;
use warnings;
use Email::MIME;
use Email::Sender::Simple qw(sendmail);
use Exporter 'import';

our @EXPORT_OK = qw(send_email);

sub send_email {
    my (%params) = @_;

    my $to      = $params{to} // '';
    my $from    = $params{from} // '';
    my $subject = $params{subject} // 'No Subject';
    my $body    = $params{body} // '';

    my @to_list = ref($to) eq 'ARRAY' ? @$to : split(/\s*,\s*/, $to);
    my %seen;
    my @unique_recipients = grep { defined $_ && $_ ne '' && !$seen{$_}++ } @to_list;

    my $email = Email::MIME->create(
        header_str => [
            From    => $from,
            To      => join(',', @unique_recipients),
            Subject => $subject,
        ],
        attributes => {
            content_type => 'text/plain',
            charset      => 'UTF-8',
            encoding     => 'quoted-printable',
        },
        body_str => $body,
    );

    sendmail($email);
    return 1;
}

1;
