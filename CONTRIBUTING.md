# Contributing

Contributions are welcome when they keep nixdb small, reproducible, and safe
for existing database data.

Before submitting a change:

```console
nix fmt -- --check $(git ls-files '*.nix')
nix flake check
bash tests/cli.sh .
bash tests/no-secrets.sh .
```

Module or operator-runtime changes should also pass the optional local NixOS VM
test:

```console
nix build .#vm-integration-test --no-link --print-build-logs
```

Keep engine lifecycle and authentication in its own file under
`modules/nixdb/engines/`. Core consumes only normalized metadata. Version
changes must be explicit, independently pinned, and documented. Manticore
bundle components move together according to upstream compatibility.

Deployment changes must compare candidate database versions before
`nixos-rebuild test`, preserve the host lock during planning, and include CLI
fixtures for failure recovery and hostile input. The runtime manifest is a
public operator interface and must remain free of credentials.

Never add real credentials, hostnames, addresses, hardware configuration,
project IDs, data paths, logs, or database data to fixtures and examples. Use
obviously fake values such as `db-host`, project IDs starting at 2001, and
`CHANGE_ME` passwords.

Changes to public options or operational behavior require documentation and
evaluation coverage. Keep commits focused and do not commit intentionally
broken configurations or generated `result` links.
