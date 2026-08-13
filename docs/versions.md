# Version management

The project deliberately treats these as independent choices:

```text
NixOS/nixpkgs != MongoDB != MySQL != Manticore bundle != Redis != Dragonfly
```

Declared versions live in `versions/default.nix`. MongoDB and MySQL use
separate locked nixpkgs inputs. Manticore uses a repository-owned, hash-pinned
package expression. Module assertions reject a package whose version differs
from its declaration.

The three nixpkgs input URLs in `flake.nix` intentionally contain immutable
revisions. Therefore an engine update has two explicit parts: edit only the
relevant input URL, then refresh only its lock node. A lock-update command alone
cannot move an input whose URL still names the old immutable revision.

## Inspecting pins

```console
cat versions/default.nix
nix flake metadata --json | jq '.locks.nodes | {nixpkgs, "mongodb-nixpkgs", "mysql-nixpkgs"}'
nixdb versions
```

## NixOS/project nixpkgs only

1. Edit only `inputs.nixpkgs.url` in `flake.nix` to the intended immutable
   nixpkgs revision.
2. Run `nix flake update nixpkgs`.
3. Review `flake.lock`, run all checks, and test a downstream NixOS build.

Do not change `mongodb-nixpkgs`, `mysql-nixpkgs`, or Manticore declarations in
this workflow.

## MongoDB only

1. Find a nixpkgs revision whose `mongodb-ce` package is the intended version.
2. Edit only `inputs.mongodb-nixpkgs.url` and `versions.mongodb`.
3. Run `nix flake update mongodb-nixpkgs`.
4. Build `.#mongodb`, run all checks, and follow MongoDB's supported upgrade
   and backup procedure before an existing data directory sees the binary.

The module asserts that the selected package version equals
`versions.mongodb`.

## MySQL only

1. Find a nixpkgs revision whose `mysql84` package is the intended version.
2. Edit only `inputs.mysql-nixpkgs.url` and `versions.mysql`.
3. Run `nix flake update mysql-nixpkgs`.
4. Build `.#mysql`, run all checks, and inspect upstream format/rollback
   compatibility before using an existing data directory.

The module asserts that the selected package version equals `versions.mysql`.

## Redis Open Source and Dragonfly only

`packages/redis/default.nix` and `packages/dragonfly/default.nix` are
repository-owned package expressions. Redis pins the official source release,
each official bundled module source, and Cargo vendor trees. Dragonfly pins an
official immutable release artifact. Update one engine by changing its exact
upstream release/revision/hash and only its entry in `versions/default.nix`,
then build its package and run its package/runtime checks. Neither update
requires moving nixpkgs or the other engine.

The v0.3.0 pins are deliberately recorded in the package expressions and here
for review:

| Engine | Declared release | Immutable upstream source | Nix SHA-256 |
| --- | --- | --- | --- |
| Redis Open Source | 8.10.0 | `redis/redis` commit `5279a8d44818a5ca51e9abb91a9b8ce481d3c88b` | `sha256-QbV5ptqvVNWEbxircjkQ7RiHFafUkabXBaHThkQwGuw=` |
| Dragonfly | 1.40.1 | `dragonflydb/dragonfly` commit `434478e00c366c711985d0b3269023fc39db8ad1`, official `dragonfly-x86_64.tar.gz` release artifact | `sha256-/Jubb684jXANGp2WS1H1chuO/txlkjkzCwO0zoVSYd4=` |

The Redis archive is fetched from the official upstream Git repository at the
recorded commit rather than relying on a mutable branch or on a builder's
network access during the build. All bundled module and Cargo input revisions
and hashes remain adjacent to that root pin in `packages/redis/default.nix`.

## Manticore bundle only

Manticore is not a flake input. `packages/manticore/default.nix` fetches an
immutable official bundle URL with a Nix hash and publishes its component
versions as package metadata. To update it:

1. identify an official Search bundle and its exact coupled Buddy, Columnar,
   Secondary, KNN, embeddings, executor, backup, load, tzdata, and Galera set;
2. change the package version, immutable URL, hash, source package metadata,
   and `passthru.componentVersions` together;
3. make the matching changes in `versions/default.nix`;
4. build `.#manticore`, run all checks, and complete the loopback canary from
   `docs/manticore.md` before any production activation.

Flake evaluation rejects a mismatch between declared Manticore bundle metadata
and package passthru values. The module also checks the selected package and
declared Search/component versions.

## Downstream framework updates

`nixdb update` changes only the downstream host's input named by
`services.nixdb.operator.inputName`. It never edits the nixdb project's own
engine pins and never runs a general flake update. Before activation it compares
the active runtime manifest to the candidate evaluation. Any database version
or Manticore bundle change is blocked unless `--allow-db-upgrade` is explicit.

Never interpret a successful system-generation rollback as a database data or
format rollback.
