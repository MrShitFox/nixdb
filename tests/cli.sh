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
  git() {
    if [[ $1 == ls-remote ]]; then
      cat <<'EOF'
1 refs/tags/v0.2.9
2 refs/tags/v0.2.10
3 refs/tags/v0.10.0
4 refs/tags/v1.0.0-rc1
5 refs/tags/v1.0.0
6 refs/tags/version-test
7 refs/tags/vfoo
EOF
    else
      command git "$@"
    fi
  }
  [[ $(latest_stable_tag) == v1.0.0 ]]
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
  [[ $(jq -r .sourceCheckout.state <<<"$status") == 'non-git / unavailable' ]]
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

printf '1..%d\n' "$passed"
