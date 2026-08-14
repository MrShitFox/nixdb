# Changelog

## v0.3.0 - 2026-08-14

### Added

- Redis Open Source 8.10.0 with independently pinned package from immutable commit archive, separate `redis` package, version guard and flake metadata.
- Dragonfly 1.40.1 with BSL 1.1 source-available pin, separate `dragonfly` package, version guard.
- Full nixdb engine integration for both in-memory engines: NixOS modules, XFS project quotas, cgroup `MemoryHigh`/`MemoryMax`/`MemorySwapMax`/`CPUWeight`, firewall ports, normalized `instances` metadata and `nixdb` CLI/manifest.
- Redis persistence: RDB `save` rules and `dbFilename`/`rdbCompression`/`rdbChecksum`, AOF `appendOnly`/`appendFsync` `always`/`everysec`/`no`/`noAppendfsyncOnRewrite`/`autoAofRewrite*`/`aofUseRdbPreamble`, and combined RDB+AOF.
- Redis ACL: declarative `authentication` with `adminUser`/`password`, `defaultUser` and named `users` each with `commands`/`keys`/`channels` (e.g. `~app:*`, `&app:*`), rendered via `aclfile`, restart-triggered.
- Redis TLS and mutual TLS: `tls.enable`/`port`/`certFile`/`keyFile`/`caFile`/`authClients` plus `healthClientCertFile`/`healthClientKeyFile` for health probes, validated via real certs.
- Redis 8 bundled modules and features verified at runtime: `redisbloom`, `redisearch`, `rejson`, `redistimeseries` plus built-in `vector-sets`.
- Redis `maxmemory`, `maxMemoryPolicy` and `maxMemorySamples` with `maxmemory <= memoryMax` headroom assertion and engine limit reporting.
- Dragonfly snapshots: `persistence.dbFilename`, `snapshotCron`, `dfSnapshotFormat`, snapshot discovery and restore verified after restart and reboot.
- Dragonfly cache/store modes: `cacheMode` true/false with `maxmemory` semantics.
- Dragonfly ACL: declarative users with `keys` `~app:*` and `channels` `&app:*` via `aclfile`, restart and reboot persistence.
- Dragonfly TLS and mutual TLS: `tls` with `certFile`/`keyFile`/`caFile`/`authClients` and health client cert/key.
- Dragonfly Memcached listener: `memcached.port` with EOF-driven health probe.
- Dragonfly admin/metrics listener: `admin.port`.
- Dragonfly SSD tiering: `tiering.enable`/`mountPoint`/`prefix`/`maxFileSize` with validation, documented as not silently emulated.
- Native Redis `extraConfig`/`extraConfigLines` escape hatch with deterministic ownership and collision-checked directives.
- Native Dragonfly `extraFlags` escape hatch with collision-checked flags.
- XFS quota and cgroup resource integration for Redis and Dragonfly: stable `projectId`, `dataDir`/`mountPoint`/`prjquota`, `diskLimit`, per-instance `memoryHigh`/`memoryMax`/`memorySwapMax`/`cpuWeight`.
- CLI, manifest and update-guard integration: `nixdb versions`/`config`/`health`/`wait`/`restart`/`doctor`/`status` handle Redis and Dragonfly, `nixdb plan`/`update` guard `redis`/`dragonfly` versions, manifest `engineMetadata` and `internalCache` for both.

Dragonfly v1.40.1 does not support AOF. nixdb rejects Dragonfly AOF configuration instead of emulating it.

nixdb does not orchestrate Redis Sentinel/Cluster or Dragonfly HA topology.

## v0.2.3 - 2026-08-13

- manual rollback now consumes deployment-state schema v2 correctly;
- the exact recorded previous nixdb generation wins over unrelated intermediate
  NixOS generations;
- schema-v1 deployment-state compatibility is retained;
- malformed, future-schema, stale, or incomplete deployment state is not
  trusted as an exact rollback target;
- compatibility fallback diagnostics are explicit;
- rollback regression coverage is expanded;
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
