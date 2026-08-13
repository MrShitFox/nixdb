# nixdb agent instructions

nixdb is public reusable infrastructure. Read the real checkout before making
changes and keep the public/downstream boundary explicit.

Permanent invariants:

- Never delete, replace, or reinitialize existing database data.
- Never hide a migration failure by removing a data directory.
- Database versions remain explicit and independently controlled.
- Never activate a different database package version implicitly. Compare the
  active and candidate manifests before `nixos-rebuild test`.
- NixOS/system rollback does not imply database data or format rollback.
- Engine implementations remain isolated; core is engine-agnostic.
- The human-facing instance inventory belongs to the downstream host.
- Public source, tests, templates, and history contain no production values or
  credentials.
- The sanitized runtime manifest must never expose credentials.
- Read-only CLI commands must not require a Git checkout.
- Update, deploy, and rollback operations must be serialized and restore exact
  downstream source/lock state after failure.
- Backward compatibility of the public `services.nixdb` API matters; use an
  alias or documented migration before removing an option.
- XFS project IDs are stable identities. Quotas require XFS with `prjquota`.
- CPU is elastic by default: use weights, not quotas, affinity, or pinning.
- Do not silently alter ports, paths, credentials, quotas, or memory limits.
- Do not introduce containers as the database runtime.
- Build and test before switch; validate health after switch.
- New engines follow `docs/adding-engine.md` and register only normalized
  metadata with core.

Run `nix fmt -- --check $(git ls-files '*.nix')`, `nix flake check`,
`bash tests/cli.sh .`, and `bash tests/no-secrets.sh .` before committing. Run
`nix build .#vm-integration-test --no-link` after module/CLI runtime changes.
Live-host validation is needed
for changes that affect unit lifecycle, database packages, authentication,
quotas, resources, or deployment behavior.
