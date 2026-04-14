# perl-shared

`perl-shared` is a shared utility library for Perl-based automation and data-processing
scripts. It provides a small set of reusable modules for configuration loading,
Evergreen database discovery, database access, logging, email, SFTP uploads,
archive creation, file I/O, and array helpers. The goal is to centralize common
patterns and best practices in one place so that individual scripts can stay
focused on their unique logic.

## Install

From the repository root:

```bash
perl Makefile.PL
make
make test
```

To consume the modules from another repo, point Perl at the shared `lib/` directory:

```perl
use lib '/path/to/perl-shared/lib';
```

## Design Rules

- All shared modules live under the `Bibliomation::Shared::*` namespace.
- Shared modules must not depend on other `Bibliomation::Shared::*` modules.
- Utility functions are exported explicitly with `@EXPORT_OK`; consumers should import only
  what they use.
- Runtime failures raise exceptions with `die`. Callers should wrap external effects in
  `eval` or `Try::Tiny` when recovery is needed.
- Shared modules should not perform application logging; consumers own logging behavior.
- Database configuration is normalized to the same shape everywhere:

```perl
{
    host     => 'db.example.org',
    port     => 5432,
    name     => 'evergreen',
    user     => 'evergreen',
    password => 'secret',
}
```

## Module Overview

### `Bibliomation::Shared::Archive`

Exports:

- `create_tar_gz_archive(%args)`

Required arguments:

- `files`
- `output_path`

Optional arguments:

- `member_paths`
- `preserve_paths`

Behavior:

- Creates a gzip-compressed tar archive from one or more local files.
- Stores file basenames in the archive by default.
- Supports explicit archive member paths when consumers need stable internal names.
- Returns the output archive path.

Example:

```perl
use Bibliomation::Shared::Archive qw(create_tar_gz_archive);

my $archive = create_tar_gz_archive(
    files       => ['/tmp/report.tsv', '/tmp/summary.tsv'],
    output_path => '/tmp/export.tar.gz',
);
```

### `Bibliomation::Shared::ArrayUtils`

Exports:

- `dedupe_array($arrayref)`

Behavior:

- Returns a sorted arrayref of unique scalar values.
- `undef` input is treated as an empty array.

Example:

```perl
use Bibliomation::Shared::ArrayUtils qw(dedupe_array);

my $unique_ids = dedupe_array([5, 2, 5, 1]);
```

### `Bibliomation::Shared::ConfigFile`

Exports:

- `load_config($path)`

Behavior:

- Parses simple `key = value` files.
- Supports unquoted values plus single-quoted and double-quoted values.
- Ignores blank lines and `#` comments.
- Accepts keys like `remote_directory`, `smtp-host`, and `config.version`.
- Dies on missing files or malformed lines.

Example:

```perl
use Bibliomation::Shared::ConfigFile qw(load_config);

my $config = load_config('/etc/my-job.conf');
```

### `Bibliomation::Shared::Evergreen`

Exports:

- `get_database_configuration($opensrf_xml_path)`
- `get_org_units($dbh, $librarynames, $include_descendants)`

Behavior:

- Reads Evergreen's `opensrf.xml`.
- Looks for database settings in `open-ils.cstore`, then `open-ils.storage`,
  then reporter config.
- Returns the normalized database config hash shown above.
- Resolves one or more Evergreen org unit shortnames to their numeric IDs.
- Accepts a comma-delimited shortname string and normalizes whitespace and case.
- Optionally includes descendants from `actor.org_unit_descendants`.
- Returns a sorted, deduplicated arrayref of org unit IDs.

Example:

```perl
use Bibliomation::Shared::Evergreen qw(get_database_configuration get_org_units);

my $db_config = get_database_configuration('/openils/conf/opensrf.xml');
my $org_units = get_org_units($dbh, 'BR1, BR2', 1);
```

### `Bibliomation::Shared::Database`

Exports:

- `setup_database_connection($db_config)`
- `run_sql($sql, @bind_params)`
- `run_sql_file($path, @bind_params)`
- `stream_id_chunks(%args)`
- `run_query_for_ids(%args)`
- `run_chunked_id_query(%args)`
- `prepare_sql($sql)`
- `execute_prepared($sth, @bind_params)`
- `begin_transaction()`
- `commit_transaction()`
- `rollback_transaction()`

Behavior:

- Maintains a module-level PostgreSQL DBI handle.
- `run_sql` returns an arrayref of hashrefs for result-set statements and a row count for
  non-result statements.
- `run_sql_file` loads SQL from disk, strips block comments, line comments, and standalone
  `BEGIN`/`COMMIT`/`ROLLBACK` wrappers, then executes the remaining statement.
- `stream_id_chunks` streams a large ID query without materializing the full ID list first.
- `run_query_for_ids` expands `:id_list` into the right number of placeholders and preserves
  bind parameter order based on the SQL text.
- `run_chunked_id_query` combines the two helpers for the common "query IDs, then query
  details in batches" workflow.

Example:

```perl
use Bibliomation::Shared::Database qw(
    setup_database_connection
    run_chunked_id_query
);
use Bibliomation::Shared::Evergreen qw(get_database_configuration);

my $db_config = get_database_configuration('/openils/conf/opensrf.xml');
setup_database_connection($db_config);

my $rows = run_chunked_id_query(
    id_sql             => 'SELECT id FROM actor.usr WHERE deleted = FALSE',
    detail_sql         => 'SELECT id, usrname FROM actor.usr WHERE id IN (:id_list)',
    chunk_size         => 1000,
    detail_bind_params => [],
);
```

### `Bibliomation::Shared::Logging`

Exports:

- `setup_logger($path)`
- `configure_logger(%opts)`
- `log_message($level, $message)`
- `log_header($level, $title, $message)`
- `DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`

Behavior:

- Writes plain log lines or boxed headers.
- Supports separate thresholds for file output and console output.
- `setup_logger` is optional; if you skip it, logs only go to the console when console
  logging is enabled.

Example:

```perl
use Bibliomation::Shared::Logging qw(
    setup_logger
    configure_logger
    log_message
    log_header
    INFO
);

setup_logger('/var/log/my-job.log');
configure_logger(console => 1, console_level => 'INFO', file_level => 'DEBUG');

log_header(INFO, 'Job Started', 'Beginning nightly export');
log_message(INFO, 'Connected to Evergreen');
```

### `Bibliomation::Shared::Email`

Exports:

- `send_email(%args)`

Required arguments:

- `from`
- `to`
- one of `body`, `text_body`, or `html_body`

Optional arguments:

- `subject`
- `cc`
- `bcc`
- `reply_to`
- `text_body`
- `html_body`

Behavior:

- Accepts recipients as either a comma-delimited string or an arrayref.
- Deduplicates recipients within each header.
- Sends plain text when only `body` or `text_body` is supplied.
- Sends HTML when only `html_body` is supplied.
- Sends multipart/alternative when both `text_body` and `html_body` are supplied.

Example:

```perl
use Bibliomation::Shared::Email qw(send_email);

send_email(
    from      => 'robot@example.org',
    to        => ['ops@example.org', 'admin@example.org'],
    subject   => 'Nightly Export Complete',
    text_body => "The export completed successfully.\n",
    html_body => '<p>The export completed successfully.</p>',
);
```

### `Bibliomation::Shared::FileIO`

Exports:

- `read_text_file($path)`
- `write_text_file(%args)`
- `append_text_file(%args)`
- `write_delimited_file(%args)`

Behavior:

- Reads and writes plain text files.
- Writes delimited text output such as TSV or CSV.
- Supports optional headers, UTF-8 output, newline sanitization, and field quoting.
- Returns the target file path from write operations.

Example:

```perl
use Bibliomation::Shared::FileIO qw(write_delimited_file);

my $path = write_delimited_file(
    path    => '/tmp/export.tsv',
    columns => [qw(id name)],
    rows    => [
        [1, 'Alpha'],
        [2, 'Beta'],
    ],
);
```

### `Bibliomation::Shared::SFTP`

Exports:

- `sftp_upload(%args)`

Required arguments:

- `host`
- `user`
- `password`
- `remote_dir`
- `files`

Optional arguments:

- `port`

Behavior:

- Accepts a single local file path or an arrayref of local file paths.
- Validates that the local files exist before uploading.
- Returns an arrayref of uploaded remote paths.

Example:

```perl
use Bibliomation::Shared::SFTP qw(sftp_upload);

my $uploaded = sftp_upload(
    host       => 'sftp.example.org',
    user       => 'upload_user',
    password   => 'secret',
    remote_dir => '/incoming/libraryiq',
    files      => ['/tmp/export.tar.gz'],
);
```

## Development

Repository layout:

- `lib/` shared modules
- `t/` tests
- `Makefile.PL` distribution metadata
- `cpanfile` runtime and test dependencies
- `Changes` release notes

Run the test suite with:

```bash
prove -lr t
```
