# perl-shared

Shared Perl modules used across Bibliomation and other Evergreen-related projects.

## Layout

- `lib/` - Namespaced Perl modules
- `t/` - Test files
- `Makefile.PL` - Build and install metadata
- `cpanfile` - Dependency declarations
- `Changes` - Release notes

## Quick Start

```bash
perl Makefile.PL
make
make test
```