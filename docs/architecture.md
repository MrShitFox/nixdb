# Architecture

nixdb is a reusable flake, not a host configuration repository.

```text
flake.nix                     public module, packages, checks, templates
modules/nixdb/core/           engine-agnostic metadata consumers
modules/nixdb/engines/        isolated engine lifecycle and authentication
packages/{manticore,redis,dragonfly}/ immutable engine packaging
packages/nixdb-cli/           downstream-host operator CLI
versions/                     declared database component versions
lib/                          small evaluation helpers
examples/                     fake, non-production configurations
templates/                    downstream host skeleton
tests/                        CLI, module, secret, and NixOS VM checks
docs/                         detailed documentation
```

The flake exports `nixosModules.default`. Importing it injects nixdb's pinned
database packages, version metadata, and CLI into the module implementation.
The downstream host supplies all instances through `services.nixdb`.

## Core contract

Each engine contributes entries to the internal normalized list. An entry
contains only:

- instance kind, name, and generated service name;
- data directory and declared mount point;
- XFS project ID and hard quota;
- all listeners and firewall-exposed ports;
- CPU weight, cgroup limits, and an optional engine-level memory limit;
- sanitized engine metadata such as persistence, cache mode, and modules.

Core consumes that list to build `database.slice`, `databases.target`, system
users, quota units, assertions, and firewall rules. Core does not inspect
MongoDB users, MySQL initialization, or Manticore Buddy.

The `_internal` option is an implementation seam for engine modules, not a
supported downstream user interface.

## Host boundary

A downstream host repository owns:

- `hardware-configuration.nix` and boot/network settings;
- filesystem devices and mount options;
- all instance inventory and credentials;
- resource and exposure policy;
- its own `flake.lock`, including the exact nixdb release revision.

No host output is exported from the public nixdb flake.

## Operator boundary

The module renders evaluated state instead of making the CLI parse downstream
Nix files:

```text
services.nixdb options
        |
        +-- /etc/nixdb/manifest.json             sanitized, mode 0444
        +-- /etc/nixdb/health-credentials.json   auth probes, mode 0400
        +-- /etc/nixdb/operator.json             runtime paths/settings
```

Manifest schema 1 carries framework identity, declared engine/bundle versions,
slice limits, operator hints, and normalized instances. Engine-specific code
may add sanitized cache or diagnostic metadata through the normalized record;
credentials are registered through a separate internal health context and can
never enter the manifest. Evaluation tests enforce this with a distinctive
fixture secret.

This boundary makes read-only CLI behavior independent of Git and the physical
layout of the downstream host files. Only deployment transactions inspect Git,
because exact source/lock restoration is part of their safety model.

## Deployment safety model

Planning evaluates a targeted nixdb input inside a temporary archived copy of
the clean downstream tree. The host lock is not changed until current and
candidate database versions have been compared. Update, deploy, and rollback
share an advisory `flock`; successful deployments record non-secret generation
and DB-version metadata under `/var/lib/nixdb`.

The DB upgrade guard prevents implicit binary changes from reaching
`nixos-rebuild test`. This protects against accidentally starting a new daemon
on an old data directory, but it is not a migration planner, backup system, or
proof that an explicitly accepted upgrade is safe. NixOS rollback similarly
cannot undo database writes or file-format changes.
