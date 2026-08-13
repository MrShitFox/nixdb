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
  only revisions, configured input metadata, lock hash, versions, generations,
  timestamps, and whether a database upgrade occurred. Writes use a mode-0600
  temporary file and rename. The schema is validated before use. These are
  advisory operational evidence, not a second configuration source of truth.

## Daily commands

```console
sudo nixdb status
sudo nixdb status --json
sudo nixdb health
sudo nixdb wait
sudo nixdb wait <instance> --timeout 90
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

`wait` is read-only and validates the instance name against the evaluated
manifest. It waits for each selected service to be active, all configured
listeners to be available, and then an authenticated engine probe: MongoDB
`ping`, MySQL `SELECT VERSION(),1` (including the documented RSA-key path), or
Manticore SQL `SHOW STATUS`/`SHOW VERSION` plus authenticated HTTP. It uses a
60-second default bounded timeout and one-second retry interval. Healthy
services return on their first probe; a timeout preserves the final probe error
instead of hiding a permanent failure. `restart` uses the same readiness check
before full health.

`doctor` checks the operator environment and prerequisites: NixOS/systemd,
manifest schema, configured mounts, XFS plus `prjquota`, the config root,
required commands, and the flake input needed for deployment. It does not
connect to databases or change the system. Deployment metadata diagnostics
distinguish a missing config root, non-Git checkout, missing input/lock, and
metadata that requires root; the latter does not make unrelated runtime checks
fail.

The read-only commands and validated `logs`/`restart` instance lookup use the
manifest rather than parsing Nix source. They work without `.git`; `status`
reports whether the root is missing, inaccessible, non-Git, or available.
Update, deploy, and rollback require Git because their transaction restores
exact downstream source state.

## Planning

```console
nixdb plan             # newest stable release
nixdb plan --latest    # same selection, explicitly
nixdb plan --main      # public development branch
nixdb plan v0.2.2      # exact tag or revision
```

Planning requires a clean downstream checkout but does not mutate it. nixdb
archives the tracked host source into a mode-0700 temporary directory, creates
a candidate lock there, evaluates the candidate manifest, compares database
versions, prints current and candidate flake inputs, and removes the temporary
state. It does not activate systemd or connect to databases.

When a root-owned config checkout cannot be read by the invoking operator,
`nixdb plan` transparently re-executes through `sudo` with all `NIXDB_*`
environment overrides removed. If the checkout is already readable, it does not
unnecessarily prompt for sudo. Thus `nixdb plan --latest` is safe to use from a
normal shell without remembering a special privilege rule.

Status is deliberately split into independent facts: configured input (the
declaration in `flake.lock`), locked revision, resolved stable release for that
revision (`untagged` if no matching stable tag is known), installed runtime
version/revision, and deployment state. JSON reports the same values as typed
fields; unavailable metadata is `null`, never a misleading placeholder.

Stable auto-selection accepts only tags matching
`^v[0-9]+\.[0-9]+\.[0-9]+$` and applies version sorting. Tags such as
`v1.0.0-rc1`, `v1.0.0-pre`, or `version-test` are never selected by `update`.
They can be requested only as explicit deployment refs.

## Safe framework upgrades

```console
sudo nixdb update             # newest stable v* tag
sudo nixdb deploy v0.2.2      # exact public tag/ref
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

After the guard permits deployment, nixdb keeps the live downstream source
clean while it executes from a private candidate archive and candidate lock:

1. `nix flake check`;
2. `nixos-rebuild build`;
3. `nixos-rebuild test`;
4. full health validation;
5. `nixos-rebuild switch`;
6. full health validation;
7. only then atomically install and commit the candidate `flake.lock`, followed
   by atomic deployment-state evidence.

It never runs a general `nix flake update`. This candidate layout avoids the
normal temporary dirty-tree warning and makes the lock mutation an explicit
commit phase rather than part of evaluation. `nixos-rebuild test` is still a
runtime mutation, so the original generation, source revision, and lock backup
are recorded and recovery traps are armed before it starts. On failure or
interruption nixdb reports the failed phase, restores exact source, restores the
recorded generation if activation began, and runs recovery health through the
previous generation's CLI. The original failure code is preserved and incomplete
recovery is reported as critical. Recovery never attempts to roll back database
contents.

## Target-version bootstrap

The flake exports `packages.<system>.nixdb` and `apps.<system>.nixdb`, so a host
can execute deployment logic from the target release rather than relying on an
older installed CLI:

```console
nix run github:MrShitFox/nixdb/v0.2.2#nixdb -- help
sudo nix run github:MrShitFox/nixdb/v0.2.2#nixdb -- \
  --config-root /etc/nixos --flake-host db-host --input-name nixdb \
  deploy v0.2.2
```

The explicit `--config-root`, `--flake-host`, and `--input-name` arguments are
validated command context. For a local immutable candidate, use
`deploy --input-url path:/srv/nixdb-v0.2.2`; it evaluates and activates the
same target CLI without a publication step. No separate bootstrap updater is
maintained.

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
