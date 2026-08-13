# SPDX-License-Identifier: GPL-3.0-or-later
{
  lib,
  stdenv,
  fetchurl,
  fetchgit,
  rustPlatform,
  runCommand,
  gnutar,
  pkg-config,
  openssl,
  zstd,
  cmake,
  ninja,
  clang,
  llvmPackages,
  autoconf,
  automake,
  libtool,
  python3,
  rustc,
  cargo,
  boost,
  libevent,
  lz4,
  lua,
  systemd,
  libxcrypt,
  gperf,
  nasm,
  which,
  git,
}:

let
  version = "8.10.0";
  redisSource = fetchurl {
    # Keep the source tied to the immutable upstream release commit.  The
    # release CDN may reject a builder's generic fetch client (as seen on the
    # real acceptance host); GitHub's official Redis repository archive is
    # the same pinned source revision and remains hash-verified by Nix.
    url = "https://github.com/redis/redis/archive/5279a8d44818a5ca51e9abb91a9b8ce481d3c88b.tar.gz";
    hash = "sha256-QbV5ptqvVNWEbxircjkQ7RiHFafUkabXBaHThkQwGuw=";
  };
  redisBloomSource = fetchgit {
    url = "https://github.com/RedisBloom/RedisBloom.git";
    rev = "f3b6639002f86248f9ba39b6fafee39ca7f863b6";
    fetchSubmodules = true;
    hash = "sha256-eHZikgR/BKcmaGL/Q2f37F0/LUGithW4ThV0EcTo5GU=";
  };
  rediSearchSource = fetchgit {
    url = "https://github.com/RediSearch/RediSearch.git";
    rev = "294c88bca92b3e686d336dc165bcf68512d91ac5";
    fetchSubmodules = true;
    hash = "sha256-m6DkKB0Uebs0LIU0hW/t+x8aZTfRlG6P7pgoIBITUW4=";
  };
  redisJsonSource = fetchgit {
    url = "https://github.com/RedisJSON/RedisJSON.git";
    rev = "2f00c990070c9e242f53dfcf53e632fe42f15947";
    fetchSubmodules = true;
    hash = "sha256-k04/KkpHS9FE426iTFL8DgKDWS5rcIXRxQb5HB0+kDw=";
  };
  redisTimeSeriesSource = fetchgit {
    url = "https://github.com/RedisTimeSeries/RedisTimeSeries.git";
    rev = "66f6f219913c1fdc6a6669ca839ea06313fb9ba1";
    fetchSubmodules = true;
    hash = "sha256-pIbX2PgfcxJe7Qwty6PXb0d+bvxJuDTsZ8UZRrbHT3w=";
  };
  # RediSearch's VectorSimilarity build otherwise downloads this dependency via
  # CMake FetchContent.  Supplying it as an immutable input keeps the complete
  # Redis 8 module build network-free in the Nix sandbox.
  eveSource = fetchgit {
    url = "https://github.com/jfalcou/eve.git";
    rev = "3d5821fe770a62c01328b78bb55880b39b8a0a26";
    hash = "sha256-k7dDtLR9PoJp9SR0z4j6uNwm8JOJQiHXbr09kXtRJ7g=";
  };
  robinMapSource = fetchgit {
    url = "https://github.com/Tessil/robin-map.git";
    rev = "4ec1bf19c6a96125ea22062f38c2cf5b958e448e";
    hash = "sha256-Hkgxiq2i0TuqMK/bI5OMOn3LkmSE40NimDjK1FBZpsA=";
  };
  tomlPlusPlusSource = fetchgit {
    url = "https://github.com/marzer/tomlplusplus.git";
    rev = "c635f218c0aefc801d9748841930365e54fe3089";
    hash = "sha256-INX8TOEumz4B5coSxhiV7opc3rYJuQXT2k1BJ3Aje1M=";
  };
  fmtSource = fetchgit {
    url = "https://github.com/fmtlib/fmt.git";
    rev = "407c905e45ad75fc29bf0f9bb7c5c2fd3475976f";
    hash = "sha256-ZmI1Dv0ZabPlxa02OpERI47jp7zFfjpeWCy1WyuPYZ0=";
  };
  spdlogSource = fetchgit {
    url = "https://github.com/gabime/spdlog.git";
    rev = "6fa36017cfd5731d617e1a934f0e5ea9c4445b13";
    hash = "sha256-0rOR9G2Y4Z4OBZtUHxID0s1aXN9ejodHrurlVCA0pIo=";
  };
  # VectorSimilarity, the vector index implementation built by RediSearch,
  # fetches this during CMake configuration unless it is supplied explicitly.
  cpuFeaturesSource = fetchgit {
    url = "https://github.com/google/cpu_features.git";
    rev = "d3b2440fcfc25fe8e6d0d4a85f06d68e98312f5b";
    hash = "sha256-IBJc1sHHh4G3oTzQm1RAHHahsEECC+BDl14DHJ8M1Ys=";
  };
  pythonWithPip = python3.withPackages (ps: [ ps.pip ]);
  redisJsonCargoVendor = rustPlatform.fetchCargoVendor {
    name = "redisjson-cargo-${version}";
    src = redisJsonSource;
    hash = "sha256-yRp1DFAGyy3pJS0jRlvHGy1eLYz6IE2pi+f58CqRgIY=";
  };
  rediSearchCargoVendor = rustPlatform.fetchCargoVendor {
    name = "redisearch-cargo-${version}";
    src = rediSearchSource;
    cargoRoot = "src/redisearch_rs";
    hash = "sha256-f6NiiSo9/I/n2xeROivF3qaXRXqamwvNYfP4QzHj43U=";
  };
  fullSource =
    runCommand "redis-open-source-${version}-full-source" { nativeBuildInputs = [ gnutar ]; }
      ''
        mkdir -p "$out"
        tar -xf ${redisSource} --strip-components=1 -C "$out"

        install_module_source() {
          module="$1"
          source="$2"
          mkdir -p "$out/modules/$module"
          cp -R --no-preserve=mode "$source" "$out/modules/$module/src"
          # modules/common.mk treats this marker as the result of its networked
          # clone phase. Every source is already a fixed-output Nix input.
          touch "$out/modules/$module/src/.prepared"
        }

        install_module_source redisbloom ${redisBloomSource}
        install_module_source redisearch ${rediSearchSource}
        install_module_source redisjson ${redisJsonSource}
        install_module_source redistimeseries ${redisTimeSeriesSource}

        # VectorSimilarity applies an upstream compatibility patch to its
        # toml++ source during CMake configuration.  Fetchgit inputs are
        # immutable, so retain a writable copy in the assembled source tree.
        install -d "$out/third-party"
        cp -R --no-preserve=mode ${tomlPlusPlusSource} "$out/third-party/tomlplusplus"

        install -d "$out/modules/redisjson/src/.cargo"
        sed 's|@vendor@|${redisJsonCargoVendor}|g' \
          ${redisJsonCargoVendor}/.cargo/config.toml \
          > "$out/modules/redisjson/src/.cargo/config.toml"

        install -d "$out/modules/redisearch/src/src/redisearch_rs/.cargo"
        sed 's|@vendor@|${rediSearchCargoVendor}|g' \
          ${rediSearchCargoVendor}/.cargo/config.toml \
          > "$out/modules/redisearch/src/src/redisearch_rs/.cargo/config.toml"
      '';
in
stdenv.mkDerivation (finalAttrs: {
  pname = "redis-open-source";
  inherit version;
  src = fullSource;

  nativeBuildInputs = [
    pkg-config
    cmake
    ninja
    clang
    llvmPackages.libclang
    llvmPackages.bintools
    autoconf
    automake
    libtool
    pythonWithPip
    rustc
    cargo
    gperf
    nasm
    which
    git
  ];
  buildInputs = [
    openssl
    zstd
    boost
    libevent
    lz4
    lua
    systemd
    libxcrypt
  ];

  # Cargo configuration is assembled above from fixed-output vendor trees.
  # The Redis Makefile is also prevented from provisioning its own toolchain.
  CARGO_NET_OFFLINE = "true";
  HOME = "/build";
  dontConfigure = true;

  unpackPhase = ''
    cp -a "$src"/. .
    chmod -R u+w .
    find scripts modules -type f -name '*.sh' -exec chmod u+x {} +
  '';

  postPatch = ''
    patchShebangs .
    # Readies tries to mutate /etc/profile before it even checks the supplied
    # Python interpreter.  nixdb supplies Python and offline Cargo inputs, so
    # this host-provisioning hook must not run in a sandboxed build.
    find modules -path '*/deps/readies/shibumi/defs' -type f \
      -exec sed -i '/^setup_profile_d$/d' {} +
    # The exact ScalableVectorSearch revision bundled by RediSearch includes a
    # toml++ v3.3.0 compatibility patch.  Its normal FetchContent path cannot
    # write to an immutable Nix input; apply that upstream patch to the copied
    # source before CMake sees it.
    patch -d third-party/tomlplusplus -p1 \
      < modules/redisearch/src/deps/VectorSimilarity/deps/ScalableVectorSearch/cmake/patches/tomlplusplus_v330.patch
  '';

  buildPhase = ''
    runHook preBuild
    # RedisJSON/TimeSeries use Readies only to discover Python.  Pin it to the
    # sandboxed interpreter so Readies cannot fall back to system provisioning.
    # RediSearch otherwise FetchContent-downloads Boost during CMake configure;
    # point it at the Nix input instead.
    MYPY=${pythonWithPip}/bin/python3 \
      LIBCLANG_PATH=${llvmPackages.libclang.lib}/lib \
      CMAKE_ARGS="-DBOOST_DIR=${boost.dev}/include -DFETCHCONTENT_SOURCE_DIR_EVE=${eveSource} -DFETCHCONTENT_SOURCE_DIR_ROBINMAP=${robinMapSource} -DFETCHCONTENT_SOURCE_DIR_TOMLPLUSPLUS=$PWD/third-party/tomlplusplus -DFETCHCONTENT_SOURCE_DIR_FMT=${fmtSource} -DFETCHCONTENT_SOURCE_DIR_SPDLOG=${spdlogSource} -DFETCHCONTENT_SOURCE_DIR_CPU_FEATURES=${cpuFeaturesSource}" \
      make -j"$NIX_BUILD_CORES" \
      BUILD_TLS=yes \
      BUILD_COMPRESSION=yes \
      USE_SYSTEMD=yes \
      INSTALL_RUST_TOOLCHAIN=no \
      IGNORE_MISSING_DEPS=1 \
      REDISEARCH_GENERATE_HEADERS=0 \
      LTO=0 \
      build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -d "$out/bin" "$out/lib/redis/modules" "$out/share/redis"
    install -m755 src/redis-server src/redis-cli src/redis-benchmark \
      src/redis-check-aof src/redis-check-rdb "$out/bin/"
    ln -s redis-server "$out/bin/redis-sentinel"

    install -m755 modules/redisbloom/redisbloom.so "$out/lib/redis/modules/redisbloom.so"
    install -m755 modules/redisearch/redisearch.so "$out/lib/redis/modules/redisearch.so"
    install -m755 modules/redisjson/rejson.so "$out/lib/redis/modules/rejson.so"
    install -m755 modules/redistimeseries/redistimeseries.so "$out/lib/redis/modules/redistimeseries.so"
    install -m644 redis.conf "$out/share/redis/redis.conf"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/redis-server" --version | grep -F "v=${version}"
    "$out/bin/redis-cli" --version | grep -F "${version}"
    test -x "$out/bin/redis-benchmark"
    test -x "$out/bin/redis-check-aof"
    test -x "$out/bin/redis-check-rdb"
    test ! -L "$out/bin/redis-check-aof"
    test ! -L "$out/bin/redis-check-rdb"
    for module in redisbloom redisearch rejson redistimeseries; do
      test -s "$out/lib/redis/modules/$module.so"
    done
    install -d redis-install-check
    "$out/bin/redis-server" \
      --port 0 \
      --unixsocket "$PWD/redis-install-check/redis.sock" \
      --unixsocketperm 700 \
      --dir "$PWD/redis-install-check" \
      --save "" \
      --appendonly no \
      --daemonize yes \
      --pidfile "$PWD/redis-install-check/redis.pid" \
      --logfile "$PWD/redis-install-check/redis.log" \
      --loadmodule "$out/lib/redis/modules/redisbloom.so" \
      --loadmodule "$out/lib/redis/modules/redisearch.so" \
      --loadmodule "$out/lib/redis/modules/rejson.so" \
      --loadmodule "$out/lib/redis/modules/redistimeseries.so"
    for _ in $(seq 1 50); do
      test -S "$PWD/redis-install-check/redis.sock" && break
      sleep 0.1
    done
    test -S "$PWD/redis-install-check/redis.sock"
    modules="$("$out/bin/redis-cli" --raw -s "$PWD/redis-install-check/redis.sock" MODULE LIST)"
    for module in bf search ReJSON timeseries; do
      grep -Fxq "$module" <<<"$modules"
    done
    "$out/bin/redis-cli" -s "$PWD/redis-install-check/redis.sock" SHUTDOWN NOSAVE || true
    runHook postInstallCheck
  '';

  passthru = {
    sourceRevision = "5279a8d44818a5ca51e9abb91a9b8ce481d3c88b";
    bundledModules = [
      "redisbloom"
      "redisearch"
      "rejson"
      "redistimeseries"
    ];
    builtInFeatures = [ "vector-sets" ];
  };

  meta = {
    description = "Redis Open Source 8 with the official bundled module set";
    homepage = "https://github.com/redis/redis";
    # The upstream tri-license permits the AGPLv3 choice used for this Nix
    # package. docs/third-party.md records all current upstream alternatives.
    license = lib.licenses.agpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "redis-server";
  };
})
