# SPDX-License-Identifier: GPL-3.0-or-later
{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  zlib,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "dragonfly";
  version = "1.40.1";

  # Official, immutable Dragonfly v1.40.1 x86_64 release artifact.  nixdb
  # supports x86_64-linux only, matching the artifact's documented target.
  src = fetchurl {
    url = "https://github.com/dragonflydb/dragonfly/releases/download/v${finalAttrs.version}/dragonfly-x86_64.tar.gz";
    hash = "sha256-/Jubb684jXANGp2WS1H1chuO/txlkjkzCwO0zoVSYd4=";
  };

  unpackPhase = ''
    tar -xzf "$src"
  '';

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    stdenv.cc.cc.lib
    zlib
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 dragonfly-x86_64 "$out/bin/dragonfly"
    install -Dm644 LICENSE.md "$out/share/licenses/dragonfly/LICENSE.md"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/dragonfly" --version \
      | sed -r 's/\x1B\[[0-9;]*[mK]//g' \
      | grep -F "v${finalAttrs.version}"
    help_output="$("$out/bin/dragonfly" --help 2>&1 || true)"
    for flag in \
      bind port dir dbfilename maxmemory proactor_threads cache_mode \
      eviction_memory_budget_threshold rss_oom_deny_ratio snapshot_cron \
      df_snapshot_format s3_endpoint s3_use_https s3_sign_payload \
      s3_ec2_metadata requirepass aclfile tls tls_cert_file tls_key_file \
      tls_ca_cert_file no_tls_on_admin_port tls_replication memcached_port \
      admin_port admin_bind cluster_mode replicaof masterauth masteruser \
      tiered_prefix tiered_max_file_size tiered_offload_threshold \
      tiered_upload_threshold tiered_min_value_size tiered_max_pending_stash_bytes \
      num_shards
    do
      printf '%s\n' "$help_output" | grep -F -- "--$flag" >/dev/null
    done
    runHook postInstallCheck
  '';

  passthru.sourceRevision = "434478e00c366c711985d0b3269023fc39db8ad1";

  meta = {
    description = "Dragonfly in-memory data store";
    homepage = "https://github.com/dragonflydb/dragonfly";
    license = lib.licenses.bsl11;
    platforms = [ "x86_64-linux" ];
    mainProgram = "dragonfly";
  };
})
