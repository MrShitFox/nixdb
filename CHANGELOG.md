# Changelog

## Unreleased

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
