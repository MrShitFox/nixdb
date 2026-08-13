# Changelog

## Unreleased

### v0.2.3 candidate

#### Fixed

- manual rollback now consumes deployment-state schema v2 correctly;
- the exact recorded previous nixdb generation wins over unrelated intermediate
  NixOS generations;
- legacy schema compatibility and fallback diagnostics are improved;
- README and operator documentation are synchronized with the current CLI.

## v0.2.2 - 2026-08-13

- harden `nixdb plan` privilege handling and make it self-elevate only when
  deployment metadata needs root access;
- report configured input, locked revision, resolved release, installed runtime,
  and incomplete deployment state without treating stale input metadata as a
  locked ref;
- add bounded authenticated readiness checks and `nixdb wait` for MongoDB,
  MySQL, and Manticore Search/Buddy after activation and restart;
- evaluate build/test/switch from a private candidate checkout, keeping the
  live downstream lock clean until successful activation;
- expose the same `nixdb` CLI as a flake package and app for target-version
  bootstrap deployments;
- restore the exact system generation, source checkout, and `flake.lock` after
  a failed `nixos-rebuild test` candidate activation;
- record atomic, schema-v2 deployment-state evidence and recover transactions
  on ERR, INT, and TERM;
- report path inputs truthfully without fabricating a Git revision or tag;
- expand CLI, deployment-recovery, signal, JSON, readiness, and NixOS VM
  regression coverage.

## v0.2.1 — operator safety hardening (2026-08-13)

- add a schema-versioned, sanitized runtime manifest and Git-independent
  read-only operator commands;
- add `nixdb plan`, strict stable-tag selection, and an explicit database
  software upgrade guard before test activation;
- serialize deployment operations and strengthen lock/source/generation
  recovery plus database-aware rollback warnings;
- preserve upgrade and exact-deploy compatibility with v0.2.0, roll back to
  the recorded generation, and wait for instance listeners after restart;
- add `doctor`, JSON status/version output, CLI security regression tests,
  module/secret evaluation coverage, ShellCheck, and a NixOS VM test;
- align version-update and safe-operations documentation with the implemented
  pinning model.

## v0.2.0 — first public release

- reusable `services.nixdb` NixOS module API;
- standalone multi-instance MongoDB, MySQL, and Manticore support;
- independently pinned database packages and Manticore component bundle;
- XFS project quotas and per-instance cgroup resource controls;
- downstream-aware operator CLI with targeted framework updates and rollback;
- sanitized examples, downstream flake template, documentation, and CI.
