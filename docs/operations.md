# Operations

The operator CLI acts on a downstream host flake, not the public nixdb source
checkout. Configure the relationship under `services.nixdb.operator`.

## Daily commands

```console
sudo nixdb status
sudo nixdb health
sudo nixdb versions
sudo nixdb quotas
sudo nixdb resources
sudo nixdb config
sudo nixdb logs <instance>
sudo nixdb restart <instance>
```

`health` validates units, configured listeners, XFS/project quotas, cgroups,
authenticated MongoDB/MySQL/Manticore operations, unauthenticated rejection,
Manticore Buddy, RT tables, and HTTP.

## Safe framework upgrades

```console
sudo nixdb update             # newest stable v* tag
sudo nixdb deploy v0.2.0      # exact public tag/ref
sudo nixdb update --main      # explicit development opt-in
```

The updater requires a clean downstream Git tree. It queries public release
tags and uses `nix flake lock --override-input nixdb ...`; other inputs are not
updated. It then runs flake evaluation, NixOS build, test activation, health,
switch, and health again. The resulting lock change is committed locally.

If a gate fails, the previous lock file, host checkout, system generation, and
runtime are restored before an old-health check. Deployment never runs
`nix flake update` and never rolls back database contents.

## NixOS rollback

```console
sudo nixdb rollback
```

This switches to the previous NixOS system generation, aligns the downstream
host Git checkout when a recorded mapping is available, and runs health. It
does not restore or alter database data.

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
