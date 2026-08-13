# nixdb downstream host

This skeleton consumes nixdb as a pinned flake input. Before evaluation:

1. generate the real machine configuration with `nixos-generate-config`;
2. copy its `hardware-configuration.nix` into this directory;
3. set the hostname and `system.stateVersion` in `configuration.nix`;
4. define instances and non-example credentials in `databases.nix`;
5. ensure each database mount is XFS and mounted with `prjquota`.

Then create `flake.lock` and build:

```console
nix flake lock
sudo nixos-rebuild build --flake .#db-host
```
