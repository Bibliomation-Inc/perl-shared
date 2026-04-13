package Bibliomation::Shared::Email;

use strict;
use warnings;
use Email::MIME;
use Email::Sender::Simple qw(sendmail);
use Exporter 'import';

our @EXPORT_OK = qw(send_email);

sub send_email {
    my (%params) = @_;

    my $from    = $params{from}    // '';
    my $subject = $params{subject} // 'No Subject';
    my $reply_to = $params{reply_to};
    my $text_body = exists $params{text_body} ? $params{text_body} : $params{body};
    my $html_body = $params{html_body};

    die "send_email: 'from' is required\n" unless $from ne '';

    my $to  = _normalize_recipients('to',  $params{to},  1);
    my $cc  = _normalize_recipients('cc',  $params{cc},  0);
    my $bcc = _normalize_recipients('bcc', $params{bcc}, 0);

    die "send_email: one of 'body', 'text_body', or 'html_body' is required\n"
        unless defined $text_body || defined $html_body;

    my @header_str = (
        From    => $from,
        To      => join(', ', @$to),
        Subject => $subject,
    );

    push @header_str, (Cc => join(', ', @$cc)) if @$cc;
    push @header_str, ('Reply-To' => $reply_to) if defined $reply_to && $reply_to ne '';

    my %recipient_seen;
    my @envelope_recipients = grep { !$recipient_seen{$_}++ } (@$to, @$cc, @$bcc);

    my $email;
    if (defined $text_body && defined $html_body) {
        $email = Email::MIME->create(
            header_str => \@header_str,
            attributes => {
                content_type => 'multipart/alternative',
            },
            parts => [
                _build_part('text/plain', $text_body),
                _build_part('text/html',  $html_body),
            ],
        );
    } elsif (defined $html_body) {
        $email = Email::MIME->create(
            header_str => \@header_str,
            attributes => {
                content_type => 'text/html',
                charset      => 'UTF-8',
                encoding     => 'quoted-printable',
            },
            body_str => $html_body,
        );
    } else {
        $email = Email::MIME->create(
            header_str => \@header_str,
            attributes => {
                content_type => 'text/plain',
                charset      => 'UTF-8',
                encoding     => 'quoted-printable',
            },
            body_str => $text_body,
        );
    }

    sendmail(
        $email,
        {
            from => $from,
            to   => \@envelope_recipients,
        },
    );
    return 1;
}

sub _build_part {
    my ($content_type, $body) = @_;

    return Email::MIME->create(
        attributes => {
            content_type => $content_type,
            charset      => 'UTF-8',
            encoding     => 'quoted-printable',
        },
        body_str => $body,
    );
}

sub _normalize_recipients {
    my ($name, $value, $required) = @_;

    if (!defined $value || $value eq '') {
        die "send_email: '$name' is required\n" if $required;
        return [];
    }

    my @raw = ref($value) eq 'ARRAY' ? @$value : split(/\s*,\s*/, $value);
    my %seen;
    my @unique = grep { defined $_ && $_ ne '' && !$seen{$_}++ } @raw;

    die "send_email: '$name' must include at least one recipient\n" if $required && !@unique;
    return \@unique;
}

1;
