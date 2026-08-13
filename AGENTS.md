# nixdb agent instructions

nixdb is public reusable infrastructure. Read the real checkout before making
changes and keep the public/downstream boundary explicit.

Permanent invariants:

- Never delete, replace, or reinitialize existing database data.
- Never hide a migration failure by removing a data directory.
- Database versions remain explicit and independently controlled.
- Engine implementations remain isolated; core is engine-agnostic.
- The human-facing instance inventory belongs to the downstream host.
- Public source, tests, templates, and history contain no production values or
  credentials.
- XFS project IDs are stable identities. Quotas require XFS with `prjquota`.
- CPU is elastic by default: use weights, not quotas, affinity, or pinning.
- Do not silently alter ports, paths, credentials, quotas, or memory limits.
- Do not introduce containers as the database runtime.
- Build and test before switch; validate health after switch.
- New engines follow `docs/adding-engine.md` and register only normalized
  metadata with core.

Run `nix fmt -- --check $(git ls-files '*.nix')`, `nix flake check`, and
`bash tests/no-secrets.sh .` before committing. Live-host validation is needed
for changes that affect unit lifecycle, database packages, authentication,
quotas, resources, or deployment behavior.
