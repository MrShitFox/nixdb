# Version management

The project deliberately treats these as independent choices:

```text
NixOS/nixpkgs != MongoDB != MySQL != Manticore bundle
```

Declared versions live in `versions/default.nix`. MongoDB and MySQL use
separate locked nixpkgs inputs. Manticore uses a repository-owned, hash-pinned
package expression. Module assertions reject a package whose version differs
from its declaration.

## Updating one component

- NixOS only: update the downstream host's `nixpkgs` input. Do not update its
  `nixdb` input.
- MongoDB only: change `mongodb-nixpkgs` in nixdb's flake lock and the declared
  MongoDB version together, then test supported data-format upgrade paths.
- MySQL only: change `mysql-nixpkgs` and the declared MySQL version together;
  check upstream upgrade compatibility before touching existing data.
- Manticore only: replace the immutable release URL/hash and move every bundled
  component declaration to the exact upstream-compatible set. Validate a
  canary before any existing data directory.

`nixdb update` changes only the downstream `nixdb` input. It does not mutate
the public project's own database pins independently.

Run `nixdb versions` on a deployed host to compare declared bundle versions
with observed runtimes.
