# Architecture

nixdb is a reusable flake, not a host configuration repository.

```text
flake.nix                     public module, packages, checks, templates
modules/nixdb/core/           engine-agnostic metadata consumers
modules/nixdb/engines/        isolated engine lifecycle and authentication
packages/manticore/           immutable Manticore bundle packaging
packages/nixdb-cli/           downstream-host operator CLI
versions/                     declared database component versions
lib/                          small evaluation helpers
examples/                     fake, non-production configurations
templates/                    downstream host skeleton
tests/                        evaluation and secret-sanity checks
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
- CPU weight and memory limits.

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
