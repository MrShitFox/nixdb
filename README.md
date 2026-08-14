# nixdb

> ❄️ Declarative multi-database stack for NixOS.

Run **MongoDB · MySQL · Manticore Search · Redis · Dragonfly** as isolated, resource-controlled instances — from one Nix configuration.

[![Release](https://img.shields.io/github/v/release/MrShitFox/nixdb?label=release&color=2ea043)](https://github.com/MrShitFox/nixdb/releases/tag/v0.3.0)
[![CI](https://img.shields.io/github/actions/workflow/status/MrShitFox/nixdb/ci.yml?branch=main&label=ci)](https://github.com/MrShitFox/nixdb/actions)
[![NixOS](https://img.shields.io/badge/NixOS-5277C3?logo=nixos&logoColor=white)](https://nixos.org)
[![License](https://img.shields.io/badge/license-GPL--3.0--or--later-blue)](COPYING)
[![Engines](https://img.shields.io/badge/engines-5-informational)](#supported-engines)

```text
🗄️  5 database engines      ♻️  multiple instances per engine
💾  XFS project quotas       🧠  engine + cgroup memory limits
🩺  health / doctor / wait   🔄  guarded upgrades & rollback
🔒  auth / ACL / TLS         ❄️  pure NixOS workflow
```

One inventory. Reproducible packages. No hidden state.

---

## Quick start

**30 seconds to your first instance.**

Structure a downstream host:

```text
/etc/nixos/
├── flake.nix
├── configuration.nix
├── hardware-configuration.nix   ← generated, never faked
└── databases.nix                ← your inventory
```

**1 · `flake.nix` — pin `nixdb` v0.3.0**

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixdb.url = "github:MrShitFox/nixdb/v0.3.0";
  };

  outputs = { nixpkgs, nixdb, ... }: {
    nixosConfigurations.db-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixdb.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

New host from template:

```console
nix flake new -t github:MrShitFox/nixdb/v0.3.0#single-host ./my-db-host
nixos-generate-config --dir ./my-db-host
```

**2 · `configuration.nix` — wire the inventory**

```nix
{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./databases.nix
  ];
}
```

**3 · `databases.nix` — declare a Redis instance**

```nix
{
  services.nixdb = {
    enable = true;

    redis.instances.cache = {
      dataDir = "/var/lib/databases/redis/cache";
      mountPoint = "/";
      projectId = 2001;
      diskLimit = "20G";
      port = 6379;

      maxMemory = "4G";
      maxMemoryPolicy = "allkeys-lru";
      authentication.password = "CHANGE_ME";

      memoryHigh = "5G";
      memoryMax = "6G";
      cpuWeight = 100;
    };
  };
}
```

All required fields are explicit: `dataDir` · `mountPoint` · `projectId` · `diskLimit` · `maxMemory` · `memoryHigh` · `memoryMax` · `cpuWeight`. No implicit sizing.

**4 · Deploy**

```console
sudo nixos-rebuild switch --flake .#db-host
nixdb status
nixdb health
```

That's it. Instance is running, quota-enforced, cgroup-limited, and health-checked — declaratively.

> Credentials stay in your private host repo and never appear in the sanitized manifest or CLI output.

---

## Add another database

Mental model — one attrset per instance:

```text
services.nixdb.<engine>.instances.<name> = { ... };
```

Copy, rename, change `port` / `dataDir` / `projectId`. Nothing else.

**Redis — paranoid durability**

```nix
services.nixdb.redis.instances.paranoid = {
  dataDir = "/var/lib/databases/redis/paranoid";
  mountPoint = "/";
  projectId = 2002;
  diskLimit = "20G";
  port = 6381;
  maxMemory = "1G";
  persistence = {
    appendOnly = true;
    appendFsync = "always";
  };
  memoryHigh = "1200M";
  memoryMax = "1500M";
  cpuWeight = 100;
};
```

**Dragonfly — cache mode**

```nix
services.nixdb.dragonfly.instances.cache = {
  dataDir = "/var/lib/databases/dragonfly/cache";
  mountPoint = "/";
  projectId = 2003;
  diskLimit = "20G";
  port = 6380;
  maxMemory = "2G";
  cacheMode = true;
  memoryHigh = "2500M";
  memoryMax = "3G";
  cpuWeight = 100;
};
```

**MySQL — minimal**

```nix
services.nixdb.mysql.instances.main = {
  dataDir = "/var/lib/databases/mysql/main";
  mountPoint = "/";
  projectId = 2004;
  diskLimit = "20G";
  port = 3306;
  adminUser = "dbadmin";
  password = "CHANGE_ME";
  bufferPool = "1G";
  maxConnections = 200;
  memoryHigh = "2G";
  memoryMax = "3G";
  cpuWeight = 100;
};
```

Same file, same workflow, no new systemd boilerplate.

---

## Storage — spread across disks

Yes — put instances on different filesystems.

```nix
# fast NVMe pool
services.nixdb.redis.instances.hot = {
  dataDir = "/var/lib/databases/redis/hot";
  mountPoint = "/";
  projectId = 2010;
  diskLimit = "50G";
  # ...
};

# second SSD / data array
services.nixdb.dragonfly.instances.archive = {
  dataDir = "/data/databases/dragonfly/archive";
  mountPoint = "/data";
  projectId = 2020;
  diskLimit = "200G";
  # ...
};
```

> **nixdb does not format or partition disks.**
> NixOS mounts the filesystem (must be **XFS** with `prjquota`); nixdb manages the instance and its quota/resources on that mount.

Each `mountPoint` must be XFS with `prjquota`. nixdb assigns the stable `projectId` to `dataDir` and reapplies the hard `diskLimit` idempotently. No other filesystems are made to support project quotas.

---

## Supported engines

| Engine | Version | Highlights |
|---|---|---|
| **MongoDB** | `8.2.11` | WiredTiger `cacheGB`, auth, SSPL — review [third-party](docs/third-party.md) |
| **MySQL** | `8.4.10` | `bufferPool` · `maxConnections` · auth |
| **Manticore Search** | `28.6.6` bundle | Search + Buddy · Columnar · Secondary · KNN (coupled bundle) |
| **Redis** | `8.10.0` | ACL · TLS · AOF/RDB · eviction · 4 modules (Bloom/Search/JSON/TimeSeries) + vector-sets |
| **Dragonfly** | `1.40.1` | snapshots · cache/store · TLS · Memcached · tiering |

Versions are declared in [`versions/default.nix`](versions/default.nix) and asserted against the actual packages. No silent drift.

Full pinning details: [versions](docs/versions.md) · [redis](docs/redis.md) · [dragonfly](docs/dragonfly.md) · [manticore](docs/manticore.md)

---

## Why nixdb

Without it, every instance means hand-written config, systemd units, directories, ports, quotas, cgroup limits, health scripts, and upgrade checklists — multiplied by engines.

With nixdb:

```text
  Nix config (databases.nix)
            │
            ▼
          nixdb
            │
      ┌─────┼──────────┬────────┬──────────┬─────────┐
      ▼     ▼          ▼        ▼          ▼         ▼
  package  config  systemd  quota   cgroup   health + manifest
                                                        │
                                              /etc/nixdb/manifest.json
```

One declarative inventory → consistent, reproducible, auditable lifecycle. No containers. No orchestration magic you didn't ask for.

What you get:

- isolated engine modules, multiple instances per engine
- independently pinned packages (MongoDB/MySQL via locked nixpkgs, Redis/Dragonfly/Manticore via hash-pinned expressions)
- `CPUWeight` · `MemoryHigh` · `MemoryMax` per instance + engine-internal limits
- XFS project quotas per data directory with duplicate-port/path/ID checks at eval time
- sanitized, schema-versioned runtime manifest for operator tooling
- explicit, extension-friendly engine contract

What you don't get (by design): clustering, replication/failover orchestration, DB-content rollback, backups.

---

## Resource model

Engine limit and cgroup limit are **separate, deliberate controls**:

```text
 Redis/Dragonfly maxMemory   →   engine eviction / OOM policy
        ↓ headroom for allocator, buffers, forks, rewrites
 systemd MemoryHigh          →   reclaim pressure starts
 systemd MemoryMax           →   hard cgroup ceiling (OOM)
```

Example:

```nix
maxMemory  = "6G";   # engine
memoryHigh = "7G";   # cgroup pressure
memoryMax  = "8G";   # cgroup hard limit
```

`MemoryMax` is never derived from `maxMemory`. You keep the headroom explicit. nixdb rejects `maxMemory > memoryMax`.

This applies to every engine with an internal cache: MongoDB `cacheGB`, MySQL `bufferPool`, Redis/Dragonfly `maxMemory` — all validated against `memoryMax` before activation.

---

## Persistence

**Redis** — choose what fits the use case:

| Mode | Config |
|---|---|
| `everysec` | `appendOnly = true; appendFsync = "everysec";` |
| `always` | `appendOnly = true; appendFsync = "always";` — max durability, higher latency |
| `RDB only` | default `save` rules, `appendOnly = false` |
| `AOF + RDB` | `appendOnly = true;` + `saveRules` |
| `none` | `persistence.saveRules = [ ]; appendOnly = false;` |

> `appendFsync = "always"` fsyncs every write — not a generic power-loss guarantee beyond Redis durability semantics.

**Dragonfly v1.40.1** — no AOF. Snapshots only:

```nix
persistence = {
  dbFilename = "dump-{timestamp}";  # extensionless when dfSnapshotFormat = true
  snapshotCron = "*/5 * * * *";
};
```

nixdb rejects `persistence.aof.enable = true` on Dragonfly — no silent emulation.

Details: [docs/redis.md](docs/redis.md) · [docs/dragonfly.md](docs/dragonfly.md)

---

## Operator CLI

When `services.nixdb.operator.enable` (default `true`), `nixdb` is installed system-wide. Secrets never appear in the manifest or CLI output.

**Inspect**

```console
nixdb status              # human-readable inventory + generations
nixdb status --json
nixdb health              # authenticated probes, listeners, quotas, cgroups
nixdb doctor              # operator env & prerequisites (no DB connections)
nixdb wait                # block until all instances are ready (60s, 1s interval)
nixdb wait cache --timeout 90
nixdb versions            # declared vs. packaged vs. runtime
nixdb quotas              # XFS project quotas live
nixdb resources           # cgroups live
nixdb config              # rendered configs (sanitized)
nixdb logs  <instance>
nixdb restart <instance>  # + readiness probe before returning
```

**Deploy**

```console
nixdb plan                # newest stable vMAJOR.MINOR.PATCH (non-mutating, private tmp copy)
nixdb plan --main         # development branch
nixdb plan v0.3.0         # exact tag/ref
nixdb deploy v0.3.0
nixdb update              # newest stable via flake input
nixdb rollback            # exact recorded generation or explicit fallback
```

Read-only commands are **Git-independent** — they use `/etc/nixdb/manifest.json`. Deployment requires a clean Git checkout and is serialized via `/run/lock/nixdb-deploy.lock`.

Full workflow: [docs/operations.md](docs/operations.md)

---

## Upgrade safety

Database engine version changes are **detected before activation**.

```console
nixdb plan
# → shows every current → candidate DB version
# → if MongoDB/MySQL/Manticore/Redis/Dragonfly changes:
#   blocked before nixos-rebuild test
```

Proceed only after reading upstream migration notes and verifying backups:

```console
sudo nixdb update --allow-db-upgrade
sudo nixdb deploy v0.3.0 --allow-db-upgrade
```

- Plain `nixos-rebuild switch` stays fully NixOS-native.
- `nixdb plan` / `update` / `deploy` is the **guarded operator workflow** on top.
- Rollback restores NixOS/system configuration — **never** database contents or file formats (migration may be irreversible). Downgrade of DB binaries requires `--allow-db-binary-rollback` after compatibility review.

---

## Native escape hatches

Typed options cover common production settings. When you need more, nixdb doesn't box you in — but it does refuse silent collisions.

**Redis — `extraConfig`**

```nix
services.nixdb.redis.instances.advanced.extraConfig = {
  "notify-keyspace-events" = "Ex";
  "repl-diskless-sync-delay" = 5;
};
# extraConfigLines for directives without a simple key/value shape
```

**Dragonfly — `extraFlags`**

```nix
services.nixdb.dragonfly.instances.advanced.extraFlags = {
  "num_shards" = 2;
};
```

> *Typed options for the common case. Native directives for the rest. Collision with a nixdb-owned setting is a build-time error, never a silent override. Dragonfly flags are validated against the exact pinned binary's `--help`.*

This keeps automation safe without limiting an experienced admin.

---

## Tested for real

v0.3.0 verified on a live NixOS host:

```text
16 managed services
  MongoDB  ×5
  MySQL    ×2
  Manticore ×3
  Redis    ×4
  Dragonfly ×2
```

Covered:

- cold reboot → all instances converge
- Redis AOF (`always`/`everysec`) + RDB persistence and recovery
- Dragonfly snapshot persistence and restore
- XFS project quotas (`prjquota`) per `dataDir`
- cgroup `MemoryHigh`/`MemoryMax` pressure and OOM behavior
- ACL (users, key/channel patterns) and TLS/mTLS
- restart / readiness probes and VM integration

> No host IPs, hostnames, credentials, project IDs, or private filesystem details are disclosed. The VM check (`nix build .#vm-integration-test`) covers lifecycle/auth/resources without claiming XFS coverage it doesn't provide.

---

## Documentation

| Topic | Link |
|---|---|
| Operations & deployment | [docs/operations.md](docs/operations.md) |
| Redis | [docs/redis.md](docs/redis.md) |
| Dragonfly | [docs/dragonfly.md](docs/dragonfly.md) |
| Architecture | [docs/architecture.md](docs/architecture.md) |
| Adding an engine | [docs/adding-engine.md](docs/adding-engine.md) |
| Versions & pinning | [docs/versions.md](docs/versions.md) |
| Manticore bundle | [docs/manticore.md](docs/manticore.md) |
| Third-party licenses | [docs/third-party.md](docs/third-party.md) |
| Security | [SECURITY.md](SECURITY.md) |
| Contributing | [CONTRIBUTING.md](CONTRIBUTING.md) |
| Changelog | [CHANGELOG.md](CHANGELOG.md) |
| Examples | [examples/redis.nix](examples/redis.nix) · [examples/dragonfly.nix](examples/dragonfly.nix) |
| Template | [`nix flake new -t github:MrShitFox/nixdb/v0.3.0#single-host`](templates/single-host) |

---

## Build and test

```console
nix fmt -- --check $(git ls-files '*.nix')
nix flake check --print-build-logs
bash tests/cli.sh .
bash tests/no-secrets.sh .
nix build .#vm-integration-test --no-link --print-build-logs  # optional, after module/CLI changes
```

Only `x86_64-linux` is supported. MongoDB Community Server is SSPL-licensed — see [third-party licensing](docs/third-party.md).

---

## License

`GPL-3.0-or-later` — see [COPYING](COPYING).
Third-party database software retains its own license.
