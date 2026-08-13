# Operations

The operator CLI acts on a downstream host flake, not the public nixdb source
checkout. Configure the relationship under `services.nixdb.operator`:

```nix
services.nixdb.operator = {
  configRoot = "/etc/nixos";
  flakeHost = "db-host";
  inventoryFile = "databases.nix";
  inputName = "nixdb";
};
```

The defaults are `/etc/nixos`, the NixOS hostname, `databases.nix`, and an
input named `nixdb`. `inventoryFile` is only an operator hint; evaluated module
options remain the source of truth.

## Runtime files

- `/etc/nixdb/manifest.json` is world-readable, sanitized evaluated state with
  `schemaVersion = 1`. It contains framework and database versions, operator
  hints, slice limits, and normalized instance metadata. It never contains
  credentials.
- `/etc/nixdb/health-credentials.json` is mode `0400` and is used only by
  authenticated health probes. It reflects the project's current policy that
  credentials may exist in downstream Nix configuration.
- `/etc/nixdb/operator.json` preserves the v0.2.0 runtime configuration
  contract and points the CLI to both files.
- `/var/lib/nixdb/deployment-state.json` and per-generation records contain
  only revisions, versions, generations, timestamps, and whether a database
  upgrade occurred. They are advisory operational state, not source of truth.

## Daily commands

```console
sudo nixdb status
sudo nixdb status --json
sudo nixdb health
sudo nixdb doctor
sudo nixdb versions
sudo nixdb versions --json
sudo nixdb quotas
sudo nixdb resources
sudo nixdb config
sudo nixdb logs <instance>
sudo nixdb restart <instance>
```

`health` validates units, configured listeners, XFS/project quotas, cgroups,
authenticated MongoDB/MySQL/Manticore operations, unauthenticated rejection,
Manticore Buddy, RT tables, and HTTP.

`doctor` checks the operator environment and prerequisites: NixOS/systemd,
manifest schema, configured mounts, XFS plus `prjquota`, the config root,
required commands, and the flake input needed for deployment. It does not
connect to databases or change the system.

The read-only commands and validated `logs`/`restart` instance lookup use the
manifest rather than parsing Nix source. They work without `.git`; `status`
reports `Source checkout: non-git / unavailable`. Update, deploy, and rollback
require Git because their transaction restores exact downstream source state.

## Planning

```console
nixdb plan             # newest stable release
nixdb plan --latest    # same selection, explicitly
nixdb plan --main      # public development branch
nixdb plan v0.2.1      # exact tag or revision
```

Planning requires a clean downstream checkout but does not mutate it. nixdb
archives the tracked host source into a mode-0700 temporary directory, creates
a candidate lock there, evaluates the candidate manifest, compares database
versions, prints current and candidate flake inputs, and removes the temporary
state. It does not activate systemd or connect to databases.

Stable auto-selection accepts only tags matching
`^v[0-9]+\.[0-9]+\.[0-9]+$` and applies version sorting. Tags such as
`v1.0.0-rc1`, `v1.0.0-pre`, or `version-test` are never selected by `update`.
They can be requested only as explicit deployment refs.

## Safe framework upgrades

```console
sudo nixdb update             # newest stable v* tag
sudo nixdb deploy v0.2.1      # exact public tag/ref
sudo nixdb update --main      # explicit development opt-in
```

The updater requires root, takes `/run/lock/nixdb-deploy.lock`, and refuses a
dirty downstream Git tree. Two update/deploy/rollback operations cannot run at
the same time. It records the original commit, branch or detached state, exact
`flake.lock`, current system path/generation, and framework input before any
mutation.

Candidate analysis happens before replacing the host lock. Any change to the
declared MongoDB, MySQL, Manticore Search, or version-coupled Manticore bundle
is a database software upgrade, including patch releases. Without explicit
approval nixdb prints every current/candidate version and exits before
`nixos-rebuild test` or any candidate database daemon can start:

```console
sudo nixdb update --allow-db-upgrade
sudo nixdb deploy v0.3.0 --allow-db-upgrade
```

Use this flag only after reading upstream upgrade guidance and verifying usable
backups. nixdb does not provide a backup framework.

After the guard permits deployment, nixdb atomically installs only the
candidate downstream lock and executes, in order:

1. `nix flake check`;
2. `nixos-rebuild build`;
3. `nixos-rebuild test`;
4. full health validation;
5. `nixos-rebuild switch`;
6. full health validation.

It never runs a general `nix flake update`. A successful lock change is
committed in the downstream host repository. On failure or interruption it
restores the exact lock and checkout; if activation began, it switches back to
the recorded NixOS generation and checks health with the previous system's CLI.
The original failure code is preserved and incomplete recovery is reported as
critical. Recovery never attempts to roll back database contents.

## NixOS rollback

```console
sudo nixdb rollback
```

This switches to the previous NixOS system generation, aligns the downstream
host Git checkout when a recorded mapping is available, and runs health.

`nixdb rollback` rolls back NixOS/system configuration. It does **not** roll
back database contents or database file formats. If recorded versions differ
across generations, an older database binary may be unsafe after an irreversible
format migration. nixdb warns and blocks that binary downgrade unless the
operator explicitly supplies `--allow-db-binary-rollback` after reviewing
upstream downgrade compatibility. Missing historical metadata also produces a
warning; it is not treated as proof of safety.

## Manual downstream build

```console
nix flake check
sudo nixos-rebuild build --flake /etc/nixos#db-host
sudo nixos-rebuild test --flake /etc/nixos#db-host
sudo nixos-rebuild switch --flake /etc/nixos#db-host
sudo nixdb health
```

Inspect a failed unit with `systemctl status <instance>` and
`journalctl -b -u <instance>`. Inspect mounts with `findmnt` before debugging a
quota unit. Treat `MemoryMax` OOMs and XFS `EDQUOT` write failures as real hard
limit events, not reasons to delete data.
