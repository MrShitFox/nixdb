# Manticore package

`packages/manticore/default.nix` owns the Manticore runtime instead of relying
on the version in the host's nixpkgs. It fetches the immutable official
Manticore bundle artifact with a Nix hash, patches runtime paths, and exposes
the coupled component versions through package metadata.

The current bundle includes Manticore Search, Buddy, Columnar/Secondary/KNN
modules, embeddings, executor, backup, load, tzdata, and Galera components.
These components keep their upstream licenses; see [third-party licensing](third-party.md).

Treat the bundle as a compatibility unit. Before upgrading an existing data
directory, inspect official upgrade guidance, build the derivation, and run a
loopback-only canary covering version output, Buddy-dependent SQL, RT-table
write/read/drop, HTTP, and authentication. Never solve incompatibility by
deleting a production data directory.
