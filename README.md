# nixdb

A modular NixOS database stack for running multiple independently configured
database instances with reproducible version pinning, resource controls, and
XFS project quotas.

nixdb is a NixOS module plus an operator CLI. It currently supports standalone
MongoDB, MySQL, and Manticore Search instances. It does not provide clustering,
replication, database-content rollback, or a backup framework.

## Features

- isolated engine modules and multiple instances per engine;
- independently pinned MongoDB, MySQL, and Manticore package sources;
- a version-coupled Manticore Search, Buddy, Columnar, Secondary, and KNN bundle;
- per-instance `CPUWeight`, `MemoryHigh`, `MemoryMax`, and internal cache controls;
- XFS project quotas per data directory;
- inventory-driven services, authentication bootstrap, and firewall ports;
- evaluation-time checks for duplicate ports, paths, project IDs, and invalid resources;
- a sanitized, schema-versioned runtime manifest for operator tooling;
- Git-independent status, health, version, quota, resource, and config commands;
- deployment planning, database-upgrade guards, transaction recovery, and rollback warnings;
- a small extension contract for additional database engines.

Only Linux/NixOS on `x86_64-linux` is currently supported. MongoDB Community
Server is SSPL-licensed; review [third-party licensing](docs/third-party.md)
before adopting it.

## Install as a flake input

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixdb.url = "github:MrShitFox/nixdb/v0.2.0";
  };

  outputs = { nixpkgs, nixdb, ... }: {
    nixosConfigurations.db-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixdb.nixosModules.default
        ./configuration.nix
        ./databases.nix
      ];
    };
  };
}
```

The public API is `services.nixdb`. Host hardware, filesystems, credentials,
paths, project IDs, ports, and resource policy remain in the downstream host
repository.

Initialize a downstream skeleton with:

```console
nix flake new -t github:MrShitFox/nixdb#single-host ./my-db-host
```

The template intentionally omits `hardware-configuration.nix`. Generate the
real file with `nixos-generate-config` and never substitute fake disk UUIDs.

## Minimal inventory

The following values are deliberately non-production examples:

```nix
{
  services.nixdb = {
    enable = true;

    operator = {
      configRoot = "/etc/nixos";
      flakeHost = "db-host";
      inventoryFile = "databases.nix";
    };

    slice = {
      memoryHigh = "8G";
      memoryMax = "12G";
      memorySwapMax = "0";
    };

    mongodb.instances.mongo-example = {
      dataDir = "/srv/databases/mongodb/mongo-example";
      mountPoint = "/";
      projectId = 2001;
      diskLimit = "10G";
      bindAddress = "127.0.0.1";
      openFirewall = false;
      port = 27017;
      adminUser = "dbadmin";
      password = "CHANGE_ME";
      cpuWeight = 100;
      cacheGB = 1;
      memoryHigh = "2G";
      memoryMax = "3G";
    };
  };
}
```

The same inventory file may contain:

```nix
services.nixdb.mysql.instances.mysql-example = {
  dataDir = "/srv/databases/mysql/mysql-example";
  mountPoint = "/";
  projectId = 2002;
  diskLimit = "10G";
  port = 3306;
  adminUser = "dbadmin";
  password = "CHANGE_ME";
  cpuWeight = 100;
  bufferPool = "1G";
  maxConnections = 100;
  memoryHigh = "2G";
  memoryMax = "3G";
};

services.nixdb.manticore.instances.search-example = {
  dataDir = "/srv/databases/manticore/search-example";
  mountPoint = "/";
  projectId = 2003;
  diskLimit = "10G";
  sqlPort = 9306;
  httpPort = 9308;
  adminUser = "dbadmin";
  password = "CHANGE_ME";
  cpuWeight = 100;
  memoryHigh = "2G";
  memoryMax = "3G";
};
```

Listeners default to `127.0.0.1` and `openFirewall = false`. Remote exposure
must be an explicit downstream decision.

## Instance fields

Common fields are `dataDir`, `mountPoint`, stable `projectId`, `diskLimit`,
`cpuWeight`, `memoryHigh`, `memoryMax`, `memorySwapMax`, `adminUser`, and
`password`. MongoDB adds `port` and WiredTiger `cacheGB`; MySQL adds `port`,
`bufferPool`, and `maxConnections`; Manticore adds `sqlPort` and `httpPort`.
Every engine supports `bindAddress` and `openFirewall`.

Credentials currently become part of the downstream Nix store and host Git
history if committed. Keep that repository private, limit access, and layer a
different secret-management mechanism when your threat model requires it.

## Storage and resources

Every declared `mountPoint` must be XFS and mounted with `prjquota`. nixdb
assigns the data directory to its stable XFS project ID and reapplies the hard
quota idempotently. It does not make project quotas work on other filesystems.

`database.slice` supplies a combined memory envelope. Instances remain CPU
elastic: `CPUWeight` affects scheduling only under contention; nixdb adds no
CPU quota or pinning. `MemoryMax` may cause a cgroup OOM when exceeded. An XFS
hard quota causes later writes to fail when full. Internal database caches
should remain comfortably below `MemoryMax`.

## Operator CLI

When `services.nixdb.operator.enable` is true, the module installs `nixdb`
system-wide. Evaluated non-secret inventory is written to the schema-versioned
`/etc/nixdb/manifest.json`; health credentials are kept separately in a
root-only file. Passwords never appear in the manifest or CLI output.

```console
sudo nixdb status
sudo nixdb status --json
sudo nixdb health
sudo nixdb doctor
sudo nixdb versions
sudo nixdb quotas
sudo nixdb resources
sudo nixdb config
sudo nixdb logs mongo-example
sudo nixdb restart mongo-example
sudo nixdb plan
sudo nixdb plan --main
sudo nixdb plan v0.2.0
sudo nixdb update
sudo nixdb update --main
sudo nixdb deploy v0.2.0
sudo nixdb rollback
```

Read-only commands use the runtime manifest and continue to work when the host
configuration is not a Git checkout. Deployment commands intentionally require
a clean Git checkout.

`nixdb plan` evaluates the candidate in a private temporary copy and never
changes the host lock or activates services. `nixdb update` accepts only the
newest exact `vMAJOR.MINOR.PATCH` tag by default; prereleases require an explicit
ref. If MongoDB, MySQL, Manticore Search, or the coupled Manticore bundle changes,
deployment stops before `nixos-rebuild test`. Proceed only after reviewing the
upstream migration and backups:

```console
sudo nixdb update --allow-db-upgrade
sudo nixdb deploy v0.3.0 --allow-db-upgrade
```

The updater changes only the downstream input named `nixdb`; it never performs
a general flake update. Mutating deployment operations are serialized and use
transaction recovery. See [operations](docs/operations.md).

## Adding an instance or engine

Another instance normally requires only a new inventory entry with unique
ports, data directory, and project ID. To add a completely new engine, create
`modules/nixdb/engines/<engine>.nix`, keep its lifecycle and authentication
inside that file, and register only normalized metadata with core. See
[adding an engine](docs/adding-engine.md).

## Version management

NixOS, MongoDB, MySQL, and Manticore versions are separate decisions. Database
packages use independently locked inputs or repository-owned immutable package
expressions. Manticore's coupled components move as one validated bundle. See
[versions](docs/versions.md) and [Manticore packaging](docs/manticore.md).

## Build and test

```console
nix fmt -- --check $(git ls-files '*.nix')
nix flake check --print-build-logs
bash tests/cli.sh .
bash tests/no-secrets.sh .
```

The fast flake checks cover CLI behavior, module evaluation, ShellCheck, and
secret sanity. The real NixOS VM integration check is available separately:

```console
nix build .#vm-integration-test --no-link --print-build-logs
```

XFS project-quota acceptance still requires a real host mounted with
`prjquota`; the VM check does not pretend to validate an XFS environment it
does not provide.

Downstream host deployment:

```console
sudo nixos-rebuild build --flake .#db-host
sudo nixos-rebuild test --flake .#db-host
sudo nixos-rebuild switch --flake .#db-host
```

## Documentation

- [Architecture](docs/architecture.md)
- [Operations](docs/operations.md)
- [Version management](docs/versions.md)
- [Adding an engine](docs/adding-engine.md)
- [Manticore package](docs/manticore.md)
- [Third-party licensing](docs/third-party.md)

## License

SPDX-License-Identifier: `GPL-3.0-or-later`

nixdb is licensed under the GNU GPL v3 or later. See [COPYING](COPYING).
Third-party database software retains its own license.
