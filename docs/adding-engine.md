# Adding a database engine

Use PostgreSQL as a conceptual example; it is not implemented yet.

1. Add `modules/nixdb/engines/postgresql.nix`.
2. Define only PostgreSQL-facing options under
   `services.nixdb.postgresql`, including `instances`.
3. Generate PostgreSQL configuration, initialization, authentication, health
   semantics, and systemd units inside that module.
4. For every instance, append one normalized record to
   `services.nixdb._internal.instances` containing its service name, ports,
   listeners, data path, mount, project ID, quota, and cgroup resources.
5. Import the new module once from `modules/nixdb/default.nix`.
6. If nixpkgs cannot provide the intended immutable version, add
   `packages/postgresql/` or a dedicated flake input. Add its declared version
   to `versions/default.nix` and assert package/version equality.
7. Add fake evaluation coverage under `tests/` and documentation/examples.
8. Add downstream instances through the host's inventory.

Do not teach core PostgreSQL configuration syntax, users, migrations, or cache
settings. Do not put PostgreSQL behavior into MongoDB, MySQL, or Manticore
modules. The normalized record is the entire shared-infrastructure contract.

Review duplicate-port and project-ID assertions, firewall behavior, quota boot
ordering, initialization idempotency, and non-destructive handling of an
existing data directory before proposing the engine.
