# Third-party software and licenses

nixdb itself is GPL-3.0-or-later. That license applies to this repository's
module, package-expression, CLI, test, and documentation source. It does not
relicense database servers or artifacts fetched by Nix.

No upstream database source code is vendored in this repository. Package
expressions select or fetch upstream software using immutable Nix inputs,
versions, URLs, and hashes.

## MongoDB Community Server

- Source/package selection: the independently locked `mongodb-nixpkgs` input.
- Upstream: <https://www.mongodb.com/try/download/community>
- License: Server Side Public License 1.0 for current Community Server releases.
- Reference: <https://www.mongodb.com/legal/licensing/community-edition>

SSPL is not an OSI-approved open-source license. Users are responsible for
reviewing its terms, particularly when offering MongoDB as a service.

## MySQL Community Server

- Source/package selection: the independently locked `mysql-nixpkgs` input.
- Upstream: <https://www.mysql.com/products/community/>
- License: MySQL Community licensing, including GPL terms and separately
  licensed bundled components.
- Reference: <https://dev.mysql.com/doc/refman/8.4/en/preface.html>

## Manticore bundle

- Package expression: `packages/manticore/default.nix`.
- Artifact origin: Manticore's official package repository, pinned by URL and
  SHA-256.
- Bundle notice shipped upstream: `share/doc/manticore/BUNDLE_LICENSES`.

The upstream bundle states, among other components:

| Component | Upstream | License reference |
| --- | --- | --- |
| Manticore Search | <https://github.com/manticoresoftware/manticoresearch> | GPL-3.0-or-later |
| Manticore Buddy | <https://github.com/manticoresoftware/manticoresearch-buddy> | GPL-3.0 |
| Manticore Columnar | <https://github.com/manticoresoftware/columnar> | Apache-2.0 |
| Manticore Backup | <https://github.com/manticoresoftware/manticoresearch-backup> | GPL-3.0 |
| Manticore Executor | <https://github.com/manticoresoftware/executor> | PHP License |
| Manticore Load | <https://github.com/manticoresoftware/manticore-load> | MIT |
| Manticore tzdata | <https://github.com/manticoresoftware/manticore-tzdata> | MIT |
| Manticore Galera | <https://github.com/manticoresoftware/galera> | GPL-2.0 |

Manticore also distributes language data and linked libraries under their own
licenses, documented inside the official bundle. The package expression does
not alter those notices or terms.

Before changing an artifact or adding vendored content, inspect its exact
license and preserve all required notices. A Nix hash proves content identity;
it does not grant redistribution rights.

## Redis Open Source 8

- Package expression: `packages/redis/default.nix`.
- Source origin: official `redis/redis` commit
  `5279a8d44818a5ca51e9abb91a9b8ce481d3c88b` (Redis Open Source 8.10.0),
  fetched as an immutable hash-checked repository archive, plus the four
  official Redis 8 bundled module repositories at release-pinned revisions.
- License: Redis 8 is offered by upstream under a tri-license: Redis Source
  Available License 2.0 (RSALv2), Server Side Public License v1 (SSPLv1), or
  GNU Affero General Public License v3 (AGPLv3). The bundled module sources
  carry the same upstream licensing model:

  | Bundled module | Repository | Revision | License (same tri-license as Redis 8) |
  | --- | --- | --- | --- |
  | RedisBloom | <https://github.com/RedisBloom/RedisBloom> | `f3b6639002f86248f9ba39b6fafee39ca7f863b6` | RSALv2 / SSPLv1 / AGPLv3 |
  | RediSearch | <https://github.com/RediSearch/RediSearch> | `294c88bca92b3e686d336dc165bcf68512d91ac5` | RSALv2 / SSPLv1 / AGPLv3 |
  | RedisJSON | <https://github.com/RedisJSON/RedisJSON> | `2f00c990070c9e242f53dfcf53e632fe42f15947` | RSALv2 / SSPLv1 / AGPLv3 |
  | RedisTimeSeries | <https://github.com/RedisTimeSeries/RedisTimeSeries> | `66f6f219913c1fdc6a6669ca839ea06313fb9ba1` | RSALv2 / SSPLv1 / AGPLv3 |

  Vector sets are an in-tree Redis 8 feature, not a separate loadable module.
- Reference: <https://redis.io/legal/licenses/>.
- nixdb distribution choice: the Nix package `packages/redis/default.nix` sets
  `meta.license = lib.licenses.agpl3Only` (AGPLv3-only). That is the license
  under which nixdb distributes the built Redis binary and its bundled
  modules. It does not limit the upstream tri-license offer; downstream
  deployers must still review all three upstream options for their own use.
  `BUILD_INTEL_SVS_OPT` is not enabled in the nixdb Redis build; the build
  uses `BUILD_TLS=yes BUILD_COMPRESSION=yes USE_SYSTEMD=yes` with no
  `BUILD_INTEL_SVS_OPT` flag.

nixdb does not change, select on a user's behalf, or relicense any Redis term.
Review the current upstream terms for the intended deployment model.

## Dragonfly v1.40.1

- Package expression: `packages/dragonfly/default.nix`.
- Artifact origin: Dragonfly's official immutable GitHub release artifact,
  SHA-256 pinned by Nix.
- License: Business Source License 1.1 (BSL 1.1) — explicitly source-available,
  not OSI open-source. The pinned upstream license declares:

  - Licensor: DragonflyDB, Ltd.
  - Change Date: Nov 1, 2030 (or fourth anniversary of first distribution, whichever first).
  - Change License: Apache License 2.0.
  - Additional Use Grant: limited production use only as part of your own
    product/service, not as an in-memory data store product/service and not as
    a Service to third parties.

  nixdb's own GPL-3.0-or-later does not relicense Dragonfly; Dragonfly remains
  under BSL 1.1 as distributed by its licensor.
- Reference: <https://github.com/dragonflydb/dragonfly/blob/v1.40.1/LICENSE.md>.

Review Dragonfly's BSL additional-use grant and Change Date before deploying
it in any service model.
