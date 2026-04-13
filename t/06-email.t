use strict;
use warnings;
use Test::More;

use Bibliomation::Shared::Email qw(send_email);

sub exception (&) {
    my $code = shift;
    eval { $code->(); 1 };
    return $@;
}

my $captured_email;
{
    no warnings 'redefine';
    local *Bibliomation::Shared::Email::sendmail = sub {
        ($captured_email) = @_;
        return 1;
    };

    ok(
        send_email(
            from      => 'robot@example.org',
            to        => ['ops@example.org', 'ops@example.org', 'admin@example.org'],
            cc        => 'audit@example.org,audit@example.org',
            subject   => 'Nightly Report',
            text_body => 'Plain text version',
            html_body => '<p>HTML version</p>',
        ),
        'send_email returns success when sendmail succeeds',
    );
}

isa_ok($captured_email, 'Email::MIME');
is($captured_email->header_str('From'), 'robot@example.org', 'sets From header');
is($captured_email->header_str('To'), 'ops@example.org, admin@example.org', 'deduplicates To recipients');
is($captured_email->header_str('Cc'), 'audit@example.org', 'deduplicates Cc recipients');
like($captured_email->content_type, qr/multipart\/alternative/i, 'creates multipart email when text and html bodies are supplied');

my @parts = $captured_email->subparts;
is(scalar @parts, 2, 'multipart email has two parts');
like($parts[0]->content_type, qr/text\/plain/i, 'first part is plain text');
like($parts[1]->content_type, qr/text\/html/i, 'second part is html');

like(
    exception {
        send_email(
            to      => 'ops@example.org',
            body    => 'Missing from field',
            subject => 'Bad message',
        );
    },
    qr/'from' is required/,
    'dies when from is missing',
);

like(
    exception {
        send_email(
            from    => 'robot@example.org',
            to      => 'ops@example.org',
            subject => 'Missing body',
        );
    },
    qr/one of 'body', 'text_body', or 'html_body' is required/,
    'dies when no body is supplied',
);

done_testing();
