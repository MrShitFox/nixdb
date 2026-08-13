#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

readonly SOURCE_ROOT=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
readonly CLI_SOURCE="$SOURCE_ROOT/packages/nixdb-cli/nixdb"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

passed=0

pass() {
  passed=$((passed + 1))
  printf 'ok %d - %s\n' "$passed" "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

make_manifest() {
  local path=$1 mongo=${2:-8.2.11} mysql=${3:-8.4.10} manticore=${4:-28.6.6}
  jq -n \
    --arg mongo "$mongo" --arg mysql "$mysql" --arg manticore "$manticore" \
    '{schemaVersion:1,framework:{version:"0.2.0",revision:("a"*40)},
      operator:{configRoot:"/example",flakeHost:"db-host",configHint:"/example/databases.nix",
        inputName:"nixdb",inputUrl:"github:example/nixdb",releaseRepository:"https://example.invalid/nixdb.git"},
      slice:{memoryHigh:"4G",memoryMax:"6G",memorySwapMax:"0"},
      versions:{mongodb:$mongo,mysql:$mysql,manticore:$manticore,
        manticoreComponents:{buddy:"4.2.0",columnar:"13.8.3",secondary:"13.8.3",knn:"13.8.3",
          embeddings:"1.1.1",executor:"1.4.2",backup:"1.10.2",load:"1.25.0",tzdata:"1.0.1",galera:"3.37"}},
      instances:[{name:"mongo-example",engine:"mongodb",serviceName:"mongo-example",
        dataDir:"/srv/db",mountPoint:"/",projectId:2001,diskLimit:"2G",ports:[27017],
        listeners:[{address:"127.0.0.1",port:27017}],cpuWeight:100,memoryHigh:"1G",
        memoryMax:"2G",memorySwapMax:"0",internalCache:{kind:"WiredTiger cache",value:"1G"},
        engineMetadata:{}}]}' >"$path"
}

make_lock() {
  local path=$1 revision=${2:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}
  jq -n --arg revision "$revision" \
    '{nodes:{root:{inputs:{nixdb:"nixdb"}},nixdb:{original:{type:"github",owner:"example",repo:"nixdb",ref:"v0.2.0"},
      locked:{type:"github",owner:"example",repo:"nixdb",rev:$revision,narHash:"sha256-example"}}},root:"root",version:7}' >"$path"
}

make_repo() {
  local repo=$1
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.name Test
  git -C "$repo" config user.email test@example.invalid
  printf '{ outputs = _: {}; }\n' >"$repo/flake.nix"
  make_lock "$repo/flake.lock"
  git -C "$repo" add flake.nix flake.lock
  git -C "$repo" commit -qm initial
}

source_cli() {
  export NIXDB_SOURCE_ONLY=1
  export NIXDB_OPERATOR_CONFIG="$test_root/missing-operator.json"
  export NIXDB_MANIFEST=$1
  export NIXDB_CONFIG_ROOT=$2
  export NIXDB_HEALTH_CREDENTIALS=${NIXDB_HEALTH_CREDENTIALS:-$test_root/missing-health.json}
  export NIXDB_STATE_DIR=${NIXDB_STATE_DIR:-$test_root/state}
  export NIXDB_DEPLOY_LOCK=${NIXDB_DEPLOY_LOCK:-$test_root/nixdb-deploy.lock}
  # shellcheck source=../packages/nixdb-cli/nixdb
  source "$CLI_SOURCE"
}

manifest="$test_root/manifest.json"
make_manifest "$manifest"

test_stable_tag_filter_and_order() (
  source_cli "$manifest" "$test_root/non-git"
  tag_fixture=''
  git() {
    if [[ $1 == ls-remote ]]; then
      printf '%s\n' "$tag_fixture"
    else
      command git "$@"
    fi
  }
  tag_fixture='1 refs/tags/v0.2.9
2 refs/tags/v0.2.10'
  [[ $(latest_stable_tag) == v0.2.10 ]]
  tag_fixture='1 refs/tags/v0.2.9
2 refs/tags/v0.2.10
3 refs/tags/v0.10.0'
  [[ $(latest_stable_tag) == v0.10.0 ]]
  tag_fixture='1 refs/tags/v0.2.9
2 refs/tags/v0.2.10
3 refs/tags/v0.10.0
4 refs/tags/v1.0.0-rc1
5 refs/tags/v1.0.0
6 refs/tags/version-test
7 refs/tags/vfoo'
  [[ $(latest_stable_tag) == v1.0.0 ]]
  tag_fixture='1 refs/tags/v1.0.0-rc1
2 refs/tags/v1.0.0-beta1
3 refs/tags/v1.0.0-pre
4 refs/tags/vfoo
5 refs/tags/version-test'
  [[ -z $(latest_stable_tag) ]]
)
test_stable_tag_filter_and_order || fail 'stable tags are strictly filtered and version-sorted'
pass 'stable tags are strictly filtered and version-sorted'

test_non_git_status_and_config() (
  source_cli "$manifest" "$test_root/non-git"
  latest_stable_tag() { echo v1.0.0; }
  runtime_mongodb_version() { echo 8.2.11; }
  runtime_mysql_version() { echo 8.4.10; }
  runtime_manticore_version() { echo 28.6.6; }
  nixos-version() { echo test-nixos; }
  systemctl() {
    case "$1" in
      --failed) return 0 ;;
      is-active) echo active ;;
      *) return 0 ;;
    esac
  }
  status=$(cmd_status --json)
  [[ $(jq -r .sourceCheckout.state <<<"$status") == missing ]]
  ! grep -F password <<<"$status"
  cmd_config | grep -F '/example/databases.nix' >/dev/null
)
test_non_git_status_and_config || fail 'read-only status/config work without Git'
pass 'read-only status/config work without Git'

test_missing_manifest() (
  source_cli "$test_root/absent.json" "$test_root/non-git"
  manifest_json
)
if test_missing_manifest >/dev/null 2>&1; then
  fail 'missing manifest is rejected'
fi
pass 'missing manifest is rejected clearly'

invalid_manifest="$test_root/invalid-manifest.json"
printf '{"schemaVersion":2,"instances":[]}\n' >"$invalid_manifest"
test_invalid_schema() (
  source_cli "$invalid_manifest" "$test_root/non-git"
  manifest_json
)
if test_invalid_schema >/dev/null 2>&1; then
  fail 'incompatible manifest schema is rejected'
fi
pass 'incompatible manifest schema is rejected'

legacy_operator="$test_root/legacy-operator.json"
jq -n '{frameworkVersion:"0.2.0",frameworkRevision:("a"*40),versions:{
  mongodb:"8.2.11",mysql:"8.4.10",manticore:"28.6.6",
  manticoreBuddy:"4.2.0",manticoreColumnar:"13.8.3",manticoreSecondary:"13.8.3",
  manticoreKnn:"13.8.3",manticoreEmbeddings:"1.1.1",manticoreExecutor:"1.4.2",
  manticoreBackup:"1.10.2",manticoreLoad:"1.25.0",manticoreTzdata:"1.0.1",
  manticoreGalera:"3.37"}}' >"$legacy_operator"
test_legacy_version_fallback() (
  export NIXDB_SOURCE_ONLY=1
  export NIXDB_OPERATOR_CONFIG="$legacy_operator"
  export NIXDB_MANIFEST="$test_root/legacy-missing-manifest.json"
  export NIXDB_CONFIG_ROOT="$test_root/non-git"
  # shellcheck source=../packages/nixdb-cli/nixdb
  source "$CLI_SOURCE"
  data=$(active_version_manifest)
  [[ $(jq -r .schemaVersion <<<"$data") == 0 ]]
  [[ $(jq -r .versions.mongodb <<<"$data") == 8.2.11 ]]
  [[ $(jq -r .versions.manticoreComponents.buddy <<<"$data") == 4.2.0 ]]
)
test_legacy_version_fallback || fail 'v0.2.0 version metadata fallback failed'
pass 'planning can bootstrap safely from v0.2.0 operator version metadata'

test_legacy_candidate_fallback() (
  source_cli "$manifest" "$test_root/non-git"
  nix() {
    if [[ $1 == eval && $2 == --json ]]; then
      return 1
    fi
    if [[ $1 == eval && $2 == --raw ]]; then
      cat "$legacy_operator"
      return
    fi
    return 99
  }
  candidate_manifest=''
  evaluate_candidate_manifest /fake-candidate
  [[ $(jq -r .schemaVersion <<<"$candidate_manifest") == 0 ]]
  [[ $(jq -r .framework.version <<<"$candidate_manifest") == 0.2.0 ]]
)
test_legacy_candidate_fallback || fail 'legacy target candidate metadata fallback failed'
pass 'exact deploy can evaluate a pre-manifest v0.2.0 candidate'

test_invalid_instances() (
  source_cli "$manifest" "$test_root/non-git"
  validate_instance 'mongo-example;touch /tmp/pwned'
)
if test_invalid_instances >/dev/null 2>&1; then
  fail 'malicious instance is rejected'
fi
pass 'malicious instance input is rejected before systemd'

test_unknown_instance() (
  source_cli "$manifest" "$test_root/non-git"
  validate_instance mysql-example
)
if test_unknown_instance >/dev/null 2>&1; then
  fail 'unknown instance is rejected'
fi
pass 'unknown but syntactically valid instance is rejected'

listener_attempts="$test_root/listener-attempts"
printf '0\n' >"$listener_attempts"
test_restart_readiness_wait() (
  source_cli "$manifest" "$test_root/non-git"
  ss() {
    local count
    count=$(cat "$listener_attempts")
    count=$((count + 1))
    printf '%s\n' "$count" >"$listener_attempts"
    if ((count >= 2)); then
      printf 'LISTEN 0 128 127.0.0.1:27017 0.0.0.0:*\n'
    fi
  }
  systemctl() {
    [[ $1 != is-failed ]]
  }
  sleep() { :; }
  wait_instance_listeners mongo-example
)
test_restart_readiness_wait || fail 'restart readiness wait did not tolerate a delayed listener'
[[ $(cat "$listener_attempts") -ge 2 ]] || fail 'restart readiness fixture did not retry'
pass 'restart waits for delayed manifest listeners before full health'

test_refs() (
  source_cli "$manifest" "$test_root/non-git"
  validate_ref v0.2.1
  validate_ref feature/safe-test
  validate_ref aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  ! (validate_ref '--upload-pack=evil') >/dev/null 2>&1
  ! (validate_ref 'v0.2.1;touch-pwned') >/dev/null 2>&1
  ! (validate_ref 'refs/../main') >/dev/null 2>&1
)
test_refs || fail 'deployment refs are validated'
pass 'valid refs pass and option/injection-shaped refs fail'

dirty_repo="$test_root/dirty-repo"
make_repo "$dirty_repo"
touch "$dirty_repo/untracked"
test_dirty_guard() (
  source_cli "$manifest" "$dirty_repo"
  require_clean
)
if test_dirty_guard >/dev/null 2>&1; then
  fail 'dirty deployment checkout is rejected'
fi
pass 'dirty deployment checkout is rejected'

test_git_required() (
  source_cli "$manifest" "$test_root/non-git"
  require_deployment_repo
)
if test_git_required >/dev/null 2>&1; then
  fail 'mutating commands require Git'
fi
pass 'deployment commands require Git while read-only commands do not'

mock_bin="$test_root/mock-bin"
mkdir -p "$mock_bin"
cat >"$mock_bin/sudo" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$SUDO_CAPTURE"
if [ -n "${SUDO_ENV_CAPTURE:-}" ]; then
  env >"$SUDO_ENV_CAPTURE"
fi
EOF
chmod +x "$mock_bin/sudo"
sudo_capture="$test_root/sudo-args"
test_privilege_boundary() (
  source_cli "$manifest" "$test_root/non-git"
  export SUDO_CAPTURE="$sudo_capture"
  export NIXDB_CONFIG_ROOT="$test_root/attacker-controlled"
  PATH="$mock_bin:$PATH"
  need_root health
)
test_privilege_boundary
if grep -F -- '--preserve-env' "$sudo_capture" >/dev/null; then
  fail 'self-elevation preserved attacker-controlled NIXDB overrides'
fi
pass 'self-elevation drops unprivileged NIXDB environment overrides'

plan_sudo_capture="$test_root/plan-sudo-args"
plan_sudo_env="$test_root/plan-sudo-env"
privilege_plan_repo="$test_root/privilege-plan-repo"
make_repo "$privilege_plan_repo"
test_plan_privilege_elevation() (
  source_cli "$manifest" "$privilege_plan_repo"
  export SUDO_CAPTURE="$plan_sudo_capture"
  export SUDO_ENV_CAPTURE="$plan_sudo_env"
  export NIXDB_CONFIG_ROOT="$test_root/attacker-controlled"
  PATH="$mock_bin:$PATH"
  is_root() { return 1; }
  git() { return 1; }
  maybe_elevate_plan plan --latest
)
test_plan_privilege_elevation || fail 'unreadable plan metadata did not self-elevate'
grep -Fx -- plan "$plan_sudo_capture" >/dev/null || fail 'plan self-elevation lost its command'
if grep -q '^NIXDB_' "$plan_sudo_env"; then
  fail 'plan self-elevation trusted NIXDB environment overrides'
fi
pass 'plan self-elevates without carrying NIXDB overrides across sudo'

test_plan_avoids_unneeded_sudo() (
  source_cli "$manifest" "$privilege_plan_repo"
  is_root() { return 1; }
  need_root() { return 97; }
  maybe_elevate_plan plan --latest
)
test_plan_avoids_unneeded_sudo || fail 'readable plan checkout unnecessarily self-elevated'
pass 'plan does not self-elevate for a readable Git checkout'

plan_repo="$test_root/plan-repo"
make_repo "$plan_repo"
candidate_manifest_file="$test_root/candidate-manifest.json"
make_manifest "$candidate_manifest_file" 8.2.12 8.4.10 28.6.6
test_plan_no_mutation() (
  source_cli "$manifest" "$plan_repo"
  before=$(sha256sum "$plan_repo/flake.lock")
  nix() {
    if [[ $1 == flake && $2 == lock ]]; then
      local tmp
      tmp=$(mktemp)
      jq '.nodes.nixdb.locked.rev = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' flake.lock >"$tmp"
      mv "$tmp" flake.lock
    elif [[ $1 == eval ]]; then
      cat "$candidate_manifest_file"
    else
      return 99
    fi
  }
  prepare_candidate v0.2.1
  after=$(sha256sum "$plan_repo/flake.lock")
  [[ "$before" == "$after" ]]
  [[ "$db_upgrade_detected" == true ]]
  git -C "$plan_repo" diff --quiet
)
test_plan_no_mutation || fail 'candidate plan is isolated from the host lock'
pass 'candidate plan detects DB changes without mutating host lock'

test_db_upgrade_guard() (
  source_cli "$manifest" "$test_root/non-git"
  current_manifest=$(cat "$manifest")
  candidate_manifest=$(cat "$candidate_manifest_file")
  db_upgrade_detected=true
  enforce_db_upgrade_guard false
)
guard_output="$test_root/guard-output"
if test_db_upgrade_guard >"$guard_output" 2>&1; then
  fail 'DB software upgrade was not blocked'
fi
grep -F 'Database software upgrade detected.' "$guard_output" >/dev/null
grep -F 'Deployment was NOT activated.' "$guard_output" >/dev/null
pass 'DB software upgrade is blocked with actionable diagnostics'

test_guard_precedes_test_activation() (
  source_cli "$manifest" "$test_root/non-git"
  current_manifest=$(cat "$manifest")
  candidate_manifest=$(cat "$candidate_manifest_file")
  db_upgrade_detected=true
  nixos-rebuild() { touch "$test_root/nixos-rebuild-was-called"; }
  deploy_candidate false
)
rm -f "$test_root/nixos-rebuild-was-called"
if test_guard_precedes_test_activation >/dev/null 2>&1; then
  fail 'guard regression fixture unexpectedly deployed'
fi
[[ ! -e "$test_root/nixos-rebuild-was-called" ]] \
  || fail 'nixos-rebuild was invoked before the DB upgrade guard'
pass 'DB version comparison blocks deployment before nixos-rebuild test'

test_db_upgrade_opt_in() (
  source_cli "$manifest" "$test_root/non-git"
  db_upgrade_detected=true
  enforce_db_upgrade_guard true
)
test_db_upgrade_opt_in || fail 'explicit DB upgrade opt-in is accepted'
pass '--allow-db-upgrade explicitly passes the pre-activation guard'

health_context="$test_root/health-context.json"
printf '{"schemaVersion":1,"instances":[]}\n' >"$health_context"
test_non_git_health() (
  export NIXDB_HEALTH_CREDENTIALS="$health_context"
  source_cli "$manifest" "$test_root/non-git"
  wait_managed_ready() { :; }
  check_units_and_ports() { :; }
  check_filesystems_and_quotas() { :; }
  check_resources() { :; }
  check_mongodb_auth() { :; }
  check_mysql_auth() { :; }
  check_manticore_auth() { :; }
  run_health | grep -F 'nixdb health: PASS' >/dev/null
)
test_non_git_health || fail 'health retains an accidental Git dependency'
pass 'health consumes runtime files and does not require Git'

active_health_system="$test_root/active-health-system"
mkdir -p "$active_health_system/sw/bin"
cat >"$active_health_system/sw/bin/nixdb" <<'EOF'
#!/bin/sh
printf 'target-generation-health\n'
EOF
chmod +x "$active_health_system/sw/bin/nixdb"
ln -s "$active_health_system" "$test_root/active-health-link"
test_active_generation_health() (
  export NIXDB_CURRENT_SYSTEM="$test_root/active-health-link"
  source_cli "$manifest" "$test_root/non-git"
  [[ $(active_system_health) == target-generation-health ]]
)
test_active_generation_health || fail 'post-activation health did not use the active generation CLI'
pass 'post-activation and rollback health use the active generation CLI'

lock_path="$test_root/nixdb-deploy.lock"
test_deployment_lock() (
  source_cli "$manifest" "$test_root/non-git"
  exec 8>"$lock_path"
  flock -n 8
  acquire_deployment_lock
)
if test_deployment_lock >/dev/null 2>&1; then
  fail 'concurrent deployment lock was not enforced'
fi
pass 'concurrent deployment operations are serialized'

failure_repo="$test_root/failure-repo"
make_repo "$failure_repo"
failure_candidate="$test_root/failure-candidate.lock"
make_lock "$failure_candidate" bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
fake_system="$test_root/fake-system"
mkdir -p "$fake_system/sw/bin" "$fake_system/bin"
printf '#!/bin/sh\nexit 0\n' >"$fake_system/sw/bin/nixdb"
printf '#!/bin/sh\nexit 0\n' >"$fake_system/bin/switch-to-configuration"
chmod +x "$fake_system/sw/bin/nixdb" "$fake_system/bin/switch-to-configuration"
ln -s "$fake_system" "$test_root/current-system"
test_failure_restore() (
  export NIXDB_CURRENT_SYSTEM="$test_root/current-system"
  source_cli "$manifest" "$failure_repo"
  work_tmp=$(mktemp -d "$test_root/deploy-work.XXXXXX")
  candidate_lock=$failure_candidate
  candidate_manifest=$(cat "$candidate_manifest_file")
  current_manifest=$(cat "$manifest")
  candidate_revision=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  plan_label=v0.2.1
  db_upgrade_detected=false
  current_generation() { echo 7; }
  run_health() { return 0; }
  nix() {
    if [[ $1 == flake && $2 == check ]]; then
      return 42
    fi
    return 0
  }
  deploy_candidate false
)
before_failure_lock=$(sha256sum "$failure_repo/flake.lock")
set +e
test_failure_restore >/dev/null 2>&1
failure_rc=$?
set -e
if ((failure_rc == 0)); then
  fail 'injected deployment failure unexpectedly succeeded'
fi
((failure_rc == 42)) || fail "deployment recovery hid original exit code $failure_rc"
after_failure_lock=$(sha256sum "$failure_repo/flake.lock")
[[ "$before_failure_lock" == "$after_failure_lock" ]] || fail 'deployment failure did not restore flake.lock exactly'
git -C "$failure_repo" diff --quiet || fail 'deployment failure left tracked changes'
pass 'deployment failure restores flake.lock and clean checkout'

rollback_repo="$test_root/rollback-repo"
make_repo "$rollback_repo"
rollback_state="$test_root/rollback-state"
mkdir -p "$rollback_state/generations" "$test_root/current-generation" "$test_root/previous-generation"
ln -s "$test_root/current-generation" "$test_root/rollback-current-system"
ln -s "$test_root/previous-generation" "$test_root/system-profile-4-link"
current_marker="$rollback_state/generations/$(basename "$test_root/current-generation").json"
target_marker="$rollback_state/generations/$(basename "$test_root/previous-generation").json"
jq -n '{dbUpgradeOccurred:true,dbVersions:{mongodb:"8.2.12"}}' >"$current_marker"
jq -n '{dbUpgradeOccurred:false,dbVersions:{mongodb:"8.2.11"}}' >"$target_marker"
test_rollback_warning() (
  export NIXDB_CURRENT_SYSTEM="$test_root/rollback-current-system"
  export NIXDB_SYSTEM_PROFILE="$test_root/system-profile"
  export NIXDB_STATE_DIR="$rollback_state"
  source_cli "$manifest" "$rollback_repo"
  nix-env() {
    printf '4 old\n5 current (current)\n'
  }
  cmd_rollback
)
rollback_output="$test_root/rollback-output"
if test_rollback_warning >"$rollback_output" 2>&1; then
  fail 'risky DB binary rollback was not blocked'
fi
grep -F 'does NOT roll back database' "$rollback_output" >/dev/null
grep -F -- '--allow-db-binary-rollback' "$rollback_output" >/dev/null
pass 'rollback warns and blocks recorded DB binary downgrade without opt-in'

target_state="$test_root/target-state"
mkdir -p "$target_state" "$test_root/recorded-current" "$test_root/recorded-previous" "$test_root/stale-newer"
ln -s "$test_root/recorded-previous" "$test_root/target-profile-4-link"
ln -s "$test_root/stale-newer" "$test_root/target-profile-5-link"
jq -n \
  --arg system "$test_root/recorded-current" \
  --arg previousSystem "$test_root/recorded-previous" \
  '{schemaVersion:1,system:$system,previous:{generation:"4",system:$previousSystem,hostRevision:("a"*40)}}' \
  >"$target_state/deployment-state.json"
test_recorded_rollback_target() (
  export NIXDB_STATE_DIR="$target_state"
  export NIXDB_SYSTEM_PROFILE="$test_root/target-profile"
  source_cli "$manifest" "$rollback_repo"
  select_rollback_target "$test_root/recorded-current" 6
  [[ "$previous_generation" == 4 ]]
  [[ "$previous_system" == "$test_root/recorded-previous" ]]
)
test_recorded_rollback_target || fail 'rollback selected a stale numerically newer generation'
pass 'rollback targets the exact recorded pre-deployment generation'

marker_state="$test_root/marker-state"
mkdir -p "$marker_state/generations" "$test_root/marker-system"
existing_marker="$marker_state/generations/$(basename "$test_root/marker-system").json"
jq -n '{schemaVersion:1,dbUpgradeOccurred:true,dbVersions:{mongodb:"8.2.12"}}' >"$existing_marker"
test_marker_preservation() (
  export NIXDB_STATE_DIR="$marker_state"
  source_cli "$manifest" "$test_root/non-git"
  record_generation_state "$test_root/marker-system" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    "$(cat "$manifest")" false
  jq -e '.dbUpgradeOccurred == true' "$existing_marker" >/dev/null
)
test_marker_preservation || fail 'existing DB-upgrade generation marker was overwritten'
pass 'later deployments preserve existing DB-upgrade generation metadata'

metadata_lock="$test_root/metadata.lock"
make_lock "$metadata_lock" bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
test_input_metadata_semantics() (
  source_cli "$manifest" "$test_root/non-git"
  release_tag_for_revision() {
    [[ $1 == bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ]] && echo v0.2.1
  }
  data=$(input_metadata_json_from "$metadata_lock")
  [[ $(jq -r .configuredInput.ref <<<"$data") == v0.2.0 ]]
  [[ $(jq -r .lockedRevision <<<"$data") == bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ]]
  [[ $(jq -r .resolvedRelease <<<"$data") == v0.2.1 ]]
  [[ $(jq -r .resolvedReleaseState <<<"$data") == tagged ]]
)
test_input_metadata_semantics || fail 'configured ref and resolved release semantics are conflated'
pass 'stale configured ref is distinct from resolved stable release'

main_lock="$test_root/main.lock"
jq '.nodes.nixdb.original.ref = "main"' "$metadata_lock" >"$main_lock"
path_lock="$test_root/path.lock"
jq -n '{nodes:{root:{inputs:{nixdb:"nixdb"}},nixdb:{original:{type:"path",path:"/srv/nixdb-v0.2.2"},locked:{type:"path",path:"/srv/nixdb-v0.2.2",narHash:"sha256-example"}}},root:"root",version:7}' >"$path_lock"
test_untagged_path_and_missing_metadata() (
  source_cli "$manifest" "$test_root/non-git"
  release_tag_for_revision() { :; }
  main_data=$(input_metadata_json_from "$main_lock")
  path_data=$(input_metadata_json_from "$path_lock")
  missing_data=$(input_metadata_json_from "$test_root/no-lock")
  [[ $(jq -r .resolvedReleaseState <<<"$main_data") == untagged ]]
  [[ $(jq -r .resolvedRelease <<<"$main_data") == null ]]
  [[ $(jq -r .resolvedReleaseState <<<"$path_data") == not-applicable ]]
  [[ $(jq -r .configuredInput.type <<<"$path_data") == path ]]
  [[ $(jq -r .resolvedReleaseState <<<"$missing_data") == unavailable ]]
  [[ $(jq -r .lockedRevision <<<"$missing_data") == null ]]
)
test_untagged_path_and_missing_metadata || fail 'untagged, path, and unavailable input metadata are ambiguous'
pass 'untagged main, path input, and missing metadata remain explicit'

status_repo="$test_root/status-repo"
make_repo "$status_repo"
status_lock="$status_repo/flake.lock"
jq '.nodes.nixdb.locked.rev = ("b" * 40)' "$status_lock" >"$status_lock.new"
mv "$status_lock.new" "$status_lock"
git -C "$status_repo" add flake.lock
git -C "$status_repo" commit -qm 'lock ahead'
test_status_json_and_ordering() (
  source_cli "$manifest" "$status_repo"
  latest_stable_tag() { echo v0.2.2; }
  release_tag_for_revision() { [[ $1 == bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ]] && echo v0.2.1; }
  runtime_mongodb_version() { echo 8.2.11; }
  runtime_mysql_version() { echo 8.4.10; }
  runtime_manticore_version() { echo 28.6.6; }
  nixos-version() { echo test-nixos; }
  systemctl() {
    case "$1" in
      --failed) return 0 ;;
      is-active) echo active ;;
      *) return 0 ;;
    esac
  }
  status=$(cmd_status --json)
  jq -e '.framework.configuredInput.ref == "v0.2.0"
    and .framework.lockedRevision == ("b" * 40)
    and .framework.resolvedRelease == "v0.2.1"
    and .framework.resolvedReleaseState == "tagged"
    and .framework.deploymentState == "lock ahead of active runtime"' <<<"$status" >/dev/null
  ! grep -F password <<<"$status"
)
test_status_json_and_ordering || fail 'status JSON does not expose truthful deployment metadata'
pass 'status JSON distinguishes configured, locked, resolved, and installed state'

test_dirty_lock_incomplete_state() (
  source_cli "$manifest" "$status_repo"
  release_tag_for_revision() { echo v0.2.1; }
  printf '\n' >>"$status_repo/flake.lock"
  source=$(source_checkout_json)
  input=$(input_metadata_json_from "$status_repo/flake.lock")
  state=$(deployment_state_json)
  [[ $(deployment_description "$(cat "$manifest")" "$input" "$source" "$state") == 'incomplete candidate activation (dirty flake.lock)' ]]
)
test_dirty_lock_incomplete_state || fail 'dirty lock after incomplete deployment is not identified'
git -C "$status_repo" reset --hard -q HEAD
pass 'dirty lock after failed legacy activation is identified as incomplete'

test_path_input_matches_active_state() (
  source_cli "$manifest" "$status_repo"
  input=$(input_metadata_json_from "$path_lock")
  source=$(source_checkout_json)
  current_system=$(readlink -f "$CURRENT_SYSTEM")
  lock_hash=$(sha256sum "$status_repo/flake.lock" | awk '{print $1}')
  state=$(jq -cn \
    --arg system "$current_system" \
    --arg lockHash "$lock_hash" \
    --arg version "$(jq -r .framework.version "$manifest")" \
    --arg revision "$(jq -r .framework.revision "$manifest")" \
    '{availability:"valid",record:{system:$system,source:{lockSha256:$lockHash},framework:{version:$version,revision:$revision}}}')
  [[ $(deployment_description "$(cat "$manifest")" "$input" "$source" "$state") == 'path input matches active system' ]]
)
test_path_input_matches_active_state || fail 'consistent path input is reported as unavailable'
pass 'status reports a consistent path candidate truthfully'

readiness_attempts="$test_root/readiness-attempts"
printf '0\n' >"$readiness_attempts"
test_manticore_readiness_retry() (
  source_cli "$manifest" "$test_root/non-git"
  instance_readiness_probe() {
    count=$(cat "$readiness_attempts")
    count=$((count + 1))
    printf '%s\n' "$count" >"$readiness_attempts"
    if ((count < 3)); then
      echo 'Buddy SHOW VERSION is not ready' >&2
      return 1
    fi
  }
  sleep() { :; }
  retry_probe 'manticore-example readiness' 5 1 instance_readiness_probe manticore-example
)
test_manticore_readiness_retry || fail 'Manticore readiness retry did not tolerate a Buddy transient'
[[ $(cat "$readiness_attempts") == 3 ]] || fail 'Manticore readiness retry count is incorrect'
pass 'Manticore Buddy readiness is retried and returns promptly when ready'

test_manticore_readiness_final_error() (
  source_cli "$manifest" "$test_root/non-git"
  instance_readiness_probe() { echo 'actual final Buddy error' >&2; return 1; }
  sleep() { SECONDS=$((SECONDS + 2)); }
  retry_probe 'manticore-example readiness' 1 1 instance_readiness_probe manticore-example
)
readiness_error="$test_root/readiness-error"
if test_manticore_readiness_final_error >"$readiness_error" 2>&1; then
  fail 'permanent Manticore readiness failure was hidden'
fi
grep -F 'actual final Buddy error' "$readiness_error" >/dev/null || fail 'final readiness error was not reported'
pass 'permanent readiness failures retain the final actual diagnostic'

test_wait_parser_and_instance_validation() (
  export NIXDB_HEALTH_CREDENTIALS="$health_context"
  source_cli "$manifest" "$test_root/non-git"
  wait_instance_ready() { [[ $1 == mongo-example && $2 == 9 ]]; }
  cmd_wait mongo-example --timeout 9 | grep -F 'mongo-example ready' >/dev/null
)
test_wait_parser_and_instance_validation || fail 'nixdb wait did not validate and dispatch its instance'
pass 'nixdb wait validates manifest instances and timeout'

test_candidate_worktree_deployment() (
  export NIXDB_CURRENT_SYSTEM="$test_root/current-system"
  source_cli "$manifest" "$failure_repo"
  work_tmp=$(mktemp -d "$test_root/candidate-worktree.XXXXXX")
  mkdir "$work_tmp/host"
  candidate_lock=$failure_candidate
  candidate_manifest=$(cat "$manifest")
  candidate_revision=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  plan_label=v0.2.2
  db_upgrade_detected=false
  current_generation() { echo 7; }
  active_system_health() { :; }
  nix() {
    [[ $1 == flake && $2 == check && $3 == "$work_tmp/host" ]] || return 91
  }
  nixos-rebuild() {
    [[ $2 == --flake && $3 == "$work_tmp/host#$FLAKE_HOST" ]] || return 92
  }
  write_deployment_state() { :; }
  record_generation_state() { :; }
  deploy_candidate false
)
candidate_before=$(git -C "$failure_repo" rev-parse HEAD)
test_candidate_worktree_deployment || fail 'deployment did not use the private candidate worktree'
[[ $(git -C "$failure_repo" rev-parse HEAD) != "$candidate_before" ]] || fail 'successful candidate test did not commit its owned lock update'
git -C "$failure_repo" reset --hard -q "$candidate_before"
pass 'flake check/build/test/switch use the private candidate worktree'

rollback_after_test_capture="$test_root/rollback-after-test"
test_post_test_failure_restores_exact_generation() (
  export NIXDB_CURRENT_SYSTEM="$test_root/current-system"
  source_cli "$manifest" "$failure_repo"
  work_tmp=$(mktemp -d "$test_root/post-test-work.XXXXXX")
  candidate_lock=$failure_candidate
  candidate_manifest=$(cat "$manifest")
  candidate_revision=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  plan_label=v0.2.2
  db_upgrade_detected=false
  current_generation() { echo 7; }
  record_generation_state() { :; }
  nix() { :; }
  nixos-rebuild() { :; }
  nix-env() {
    if [[ $1 == --switch-generation ]]; then
      printf '%s\n' "$2" >"$rollback_after_test_capture"
    fi
  }
  active_system_health() { return 55; }
  deploy_candidate false
)
before_post_test_lock=$(sha256sum "$failure_repo/flake.lock")
set +e
test_post_test_failure_restores_exact_generation >/dev/null 2>&1
post_test_rc=$?
set -e
((post_test_rc == 55)) || fail "post-test failure did not preserve original exit code $post_test_rc"
[[ $(cat "$rollback_after_test_capture") == 7 ]] || fail 'post-test failure did not restore the recorded generation'
[[ "$before_post_test_lock" == "$(sha256sum "$failure_repo/flake.lock")" ]] || fail 'post-test failure changed downstream flake.lock'
git -C "$failure_repo" diff --quiet || fail 'post-test failure left downstream source dirty'
pass 'post-test health failure restores exact prior generation and source'

atomic_state_dir="$test_root/atomic-state"
test_atomic_deployment_state() (
  export NIXDB_STATE_DIR="$atomic_state_dir"
  source_cli "$manifest" "$failure_repo"
  current_generation() { echo 8; }
  write_deployment_state "$fake_system" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "$(cat "$manifest")" false \
    "$fake_system" 7 bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  data=$(deployment_state_json)
  [[ $(jq -r .availability <<<"$data") == valid ]]
  [[ $(jq -r .record.schemaVersion <<<"$data") == 2 ]]
  [[ $(jq -r .record.source.lockSha256 <<<"$data") =~ ^[0-9a-f]{64}$ ]]
)
test_atomic_deployment_state || fail 'deployment state was not written as valid schema-versioned evidence'
pass 'deployment state records atomic schema-v2 operational evidence'

test_atomic_state_rename_failure() (
  export NIXDB_STATE_DIR="$atomic_state_dir"
  source_cli "$manifest" "$failure_repo"
  previous=$(sha256sum "$atomic_state_dir/deployment-state.json")
  current_generation() { echo 9; }
  mv() { return 1; }
  if write_deployment_state "$fake_system" bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb "$(cat "$manifest")" false \
    "$fake_system" 8 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; then
    return 1
  fi
  [[ "$previous" == "$(sha256sum "$atomic_state_dir/deployment-state.json")" ]]
)
test_atomic_state_rename_failure || fail 'deployment-state rename failure replaced the prior state'
pass 'failed atomic state write preserves the prior complete state'

printf '1..%d\n' "$passed"
