# Contributing

Contributions are welcome when they keep nixdb small, reproducible, and safe
for existing database data.

Before submitting a change:

```console
nix fmt -- --check $(git ls-files '*.nix')
nix flake check
bash tests/no-secrets.sh .
```

Keep engine lifecycle and authentication in its own file under
`modules/nixdb/engines/`. Core consumes only normalized metadata. Version
changes must be explicit, independently pinned, and documented. Manticore
bundle components move together according to upstream compatibility.

Never add real credentials, hostnames, addresses, hardware configuration,
project IDs, data paths, logs, or database data to fixtures and examples. Use
obviously fake values such as `db-host`, project IDs starting at 2001, and
`CHANGE_ME` passwords.

Changes to public options or operational behavior require documentation and
evaluation coverage. Keep commits focused and do not commit intentionally
broken configurations or generated `result` links.
