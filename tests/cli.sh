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
  local path=$1 mongo=${2:-8.2.11} mysql=${3:-8.4.10} manticore=${4:-28.6.6} redis=${5:-8.10.0} dragonfly=${6:-1.40.1}
  jq -n \
    --arg mongo "$mongo" --arg mysql "$mysql" --arg manticore "$manticore" --arg redis "$redis" --arg dragonfly "$dragonfly" \
    '{schemaVersion:1,framework:{version:"0.2.0",revision:("a"*40)},
      operator:{configRoot:"/example",flakeHost:"db-host",configHint:"/example/databases.nix",
        inputName:"nixdb",inputUrl:"github:example/nixdb",releaseRepository:"https://example.invalid/nixdb.git"},
      slice:{memoryHigh:"4G",memoryMax:"6G",memorySwapMax:"0"},
      versions:{mongodb:$mongo,mysql:$mysql,manticore:$manticore,redis:$redis,dragonfly:$dragonfly,
        manticoreComponents:{buddy:"4.2.0",columnar:"13.8.3",secondary:"13.8.3",knn:"13.8.3",
          embeddings:"1.1.1",executor:"1.4.2",backup:"1.10.2",load:"1.25.0",tzdata:"1.0.1",galera:"3.37"}},
      instances:[{name:"mongo-example",engine:"mongodb",serviceName:"mongo-example",
        dataDir:"/srv/db",mountPoint:"/",projectId:2001,diskLimit:"2G",ports:[27017],
        listeners:[{address:"127.0.0.1",port:27017}],cpuWeight:100,memoryHigh:"1G",
        memoryMax:"2G",memorySwapMax:"0",internalCache:{kind:"WiredTiger cache",value:"1G"},
        engineMemoryLimit:null,engineMetadata:{}},
      {name:"redis-example",engine:"redis",serviceName:"redis-example",
        dataDir:"/srv/redis",mountPoint:"/",projectId:2002,diskLimit:"2G",ports:[6379],
        listeners:[{address:"127.0.0.1",port:6379}],cpuWeight:100,memoryHigh:"1200M",
        memoryMax:"2G",memorySwapMax:"0",engineMemoryLimit:"1G",internalCache:{kind:"Redis maxmemory",value:"1G"},
        engineMetadata:{maxMemory:"1G",maxMemoryPolicy:"allkeys-lru",maxMemorySamples:5,persistence:"AOF",appendFsync:"always",unixSocket:null,modules:["redisbloom","redisearch","rejson","redistimeseries"]}},
      {name:"dragonfly-example",engine:"dragonfly",serviceName:"dragonfly-example",
        dataDir:"/srv/dragonfly",mountPoint:"/",projectId:2003,diskLimit:"2G",ports:[6381,11211,16379],
        listeners:[{address:"127.0.0.1",port:6381},{address:"127.0.0.1",port:11211},{address:"127.0.0.1",port:16379}],cpuWeight:100,memoryHigh:"1200M",
        memoryMax:"2G",memorySwapMax:"0",engineMemoryLimit:"1G",internalCache:{kind:"Dragonfly maxmemory",value:"1G"},
        engineMetadata:{maxMemory:"1G",cacheMode:true,snapshot:{dbFilename:"dump-{timestamp}",dfSnapshotFormat:true,snapshotCron:"*/5 * * * *"},tiering:{enable:false},memcached:{port:11211},admin:{port:16379}}}]}' >"$path"
}

make_lock() {
  local path=$1 revision=${2:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}
  jq -n --arg revision "$revision" \
    '{nodes:{root:{inputs:{nixdb:"nixdb"}},nixdb:{original:{type:"github",owner:"example",repo:"nixdb",ref:"v0.2.0"},
      locked:{type:"github",owner:"example",repo:"nixdb",rev:$revision,narHash:"sha256-example"}}},root:"root",version:7}' >"$path"
}

make_legacy_deployment_state() {
  local path=$1 system=$2 generation=$3 previous_system=$4 previous_generation=$5
  jq -n \
    --arg system "$system" \
    --arg generation "$generation" \
    --arg previousSystem "$previous_system" \
    --arg previousGeneration "$previous_generation" \
    '{schemaVersion:1,system:$system,generation:$generation,hostRevision:("a"*40),
      framework:{version:"0.2.1",revision:("b"*40)},
      dbVersions:{mongodb:"8.2.11",mysql:"8.4.10",manticore:"28.6.6"},
      timestamp:"2026-08-13T00:00:00+00:00",dbUpgradeOccurred:false,
      previous:{system:$previousSystem,generation:$previousGeneration,hostRevision:("c"*40)}}' >"$path"
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
  runtime_redis_version() { echo 8.10.0; }
  runtime_dragonfly_version() { echo 1.40.1; }
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

test_in_memory_engine_operator_output() (
  source_cli "$manifest" "$test_root/non-git"
  runtime_redis_version() { echo 8.10.0; }
  runtime_dragonfly_version() { echo 1.40.1; }
  nixos-version() { echo test-nixos; }
  versions=$(cmd_versions --json)
  jq -e '.redis.declared == "8.10.0" and .redis.runtime == "8.10.0"
    and .dragonfly.declared == "1.40.1" and .dragonfly.runtime == "1.40.1"' <<<"$versions" >/dev/null
  config=$(cmd_config)
  grep -F 'Redis instances' <<<"$config" >/dev/null
  grep -F 'Dragonfly instances' <<<"$config" >/dev/null
  grep -F 'appendfsync=always' <<<"$config" >/dev/null
  ! grep -F password <<<"$config"
)
test_in_memory_engine_operator_output || fail 'Redis and Dragonfly version/config output is incomplete or leaks secrets'
pass 'Redis and Dragonfly participate in versions and sanitized config output'

test_in_memory_runtime_versions_use_managed_services() (
  source_cli "$manifest" "$test_root/non-git"
  mkdir -p "$test_root/pinned-redis/bin" "$test_root/pinned-dragonfly/bin"
  printf '#!/usr/bin/env bash\nprintf "Redis server v=8.10.0 sha=fixture\\n"\n' \
    >"$test_root/pinned-redis/bin/redis-server"
  printf '#!/usr/bin/env bash\nprintf "dragonfly v1.40.1\\n"\n' \
    >"$test_root/pinned-dragonfly/bin/dragonfly"
  chmod +x "$test_root/pinned-redis/bin/redis-server" "$test_root/pinned-dragonfly/bin/dragonfly"
  systemctl() {
    [[ $1 == show && $3 == -p && $4 == ExecStart && $5 == --value ]] || return 1
    case "$2" in
      redis-example) printf '{ path=%s ; argv[]=fixture }\n' "$test_root/pinned-redis/bin/redis-server" ;;
      dragonfly-example) printf '{ path=%s ; argv[]=fixture }\n' "$test_root/pinned-dragonfly/bin/dragonfly" ;;
      *) return 1 ;;
    esac
  }
  [[ $(runtime_redis_version) == 8.10.0 ]]
  [[ $(runtime_dragonfly_version) == 1.40.1 ]]
)
test_in_memory_runtime_versions_use_managed_services \
  || fail 'in-memory engine runtime versions do not use their managed services'
pass 'Redis and Dragonfly runtime versions use their managed service binaries'

test_redis_cli_uses_portable_connection_options() (
  source_cli "$manifest" "$test_root/non-git"
  credential_for() {
    jq -n '{address:"127.0.0.1",ports:{redis:6379},unixSocket:null,username:"admin",password:"fixture",authenticated:true,tls:{enable:false}}'
  }
  engine_program_path() { return 1; }
  redis-cli() {
    printf '%s\n' "$*" >"$test_root/redis-cli-args"
    printf 'PONG\n'
  }
  [[ $(redis_cli_command redis-example PING) == PONG ]]
  grep -F -- '-h 127.0.0.1 -p 6379' "$test_root/redis-cli-args" >/dev/null
  ! grep -F -- '--host' "$test_root/redis-cli-args" >/dev/null
  ! grep -F -- '--port' "$test_root/redis-cli-args" >/dev/null
)
test_redis_cli_uses_portable_connection_options \
  || fail 'Redis-compatible health adapter uses unsupported redis-cli connection options'
pass 'Redis-compatible health adapter uses portable redis-cli options'

test_dragonfly_info_version_normalization() (
  source_cli "$manifest" "$test_root/non-git"
  redis_cli_command() {
    local name=$1
    shift
    case "$*" in
      PING) printf 'PONG\n' ;;
      'INFO server') printf 'dragonfly_version:df-v1.40.1\r\n' ;;
      '--raw CONFIG GET maxmemory') printf 'maxmemory\n1073741824\n' ;;
      *) return 1 ;;
    esac
  }
  probe_dragonfly_ready dragonfly-example
)
test_dragonfly_info_version_normalization \
  || fail 'Dragonfly INFO version format is not normalized for health'
pass 'Dragonfly INFO version format is normalized for health'

test_redis_info_and_config_normalization() (
  source_cli "$manifest" "$test_root/non-git"
  credential_for() { jq -n '{unixSocket:null}'; }
  redis_cli_command() {
    local name=$1
    shift
    case "$*" in
      PING) printf 'PONG\n' ;;
      'INFO server') printf 'redis_version:8.10.0\r\n' ;;
      '--raw CONFIG GET maxmemory') printf 'maxmemory\n1073741824\r\n' ;;
      '--raw CONFIG GET maxmemory-policy') printf 'maxmemory-policy\nallkeys-lru\r\n' ;;
      '--raw MODULE LIST') printf 'bf\r\nsearch\r\nReJSON\r\ntimeseries\r\n' ;;
      *) return 1 ;;
    esac
  }
  probe_redis_ready redis-example
)
test_redis_info_and_config_normalization \
  || fail 'Redis INFO or CONFIG values retain RESP CRLF in health checks'
pass 'Redis INFO and CONFIG values are normalized for health'

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

candidate_inmemory_manifest_file="$test_root/candidate-inmemory-manifest.json"
make_manifest "$candidate_inmemory_manifest_file" 8.2.11 8.4.10 28.6.6 8.10.1 1.40.2
test_in_memory_engine_upgrade_guard() (
  source_cli "$manifest" "$plan_repo"
  nix() {
    if [[ $1 == flake && $2 == lock ]]; then
      return
    elif [[ $1 == eval ]]; then
      cat "$candidate_inmemory_manifest_file"
    else
      return 99
    fi
  }
  prepare_candidate v0.3.0
  [[ "$db_upgrade_detected" == true ]]
  output=$(print_upgrade_block 2>&1)
  grep -F 'Redis:' <<<"$output" >/dev/null
  grep -F 'Dragonfly:' <<<"$output" >/dev/null
  grep -F '8.10.1' <<<"$output" >/dev/null
  grep -F '1.40.2' <<<"$output" >/dev/null
)
test_in_memory_engine_upgrade_guard || fail 'Redis and Dragonfly package changes do not join the DB upgrade guard'
pass 'Redis and Dragonfly versions are guarded before activation'

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
  check_redis_auth() { :; }
  check_dragonfly_auth() { :; }
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
make_legacy_deployment_state "$target_state/deployment-state.json" \
  "$test_root/recorded-current" 6 "$test_root/recorded-previous" 4
test_recorded_rollback_target() (
  export NIXDB_STATE_DIR="$target_state"
  export NIXDB_SYSTEM_PROFILE="$test_root/target-profile"
  source_cli "$manifest" "$rollback_repo"
  select_rollback_target "$test_root/recorded-current" 6
  [[ "$previous_generation" == 4 ]]
  [[ "$previous_system" == "$test_root/recorded-previous" ]]
)
test_recorded_rollback_target || fail 'rollback selected a stale numerically newer generation'
pass 'legacy schema-v1 state targets the exact recorded pre-deployment generation'

schema_v2_state="$test_root/schema-v2-rollback-state"
mkdir -p "$schema_v2_state" \
  "$test_root/schema-v2-current" \
  "$test_root/schema-v2-recorded-previous" \
  "$test_root/schema-v2-intermediate-21" \
  "$test_root/schema-v2-intermediate-22"
ln -s "$test_root/schema-v2-recorded-previous" "$test_root/schema-v2-profile-20-link"
ln -s "$test_root/schema-v2-intermediate-21" "$test_root/schema-v2-profile-21-link"
ln -s "$test_root/schema-v2-intermediate-22" "$test_root/schema-v2-profile-22-link"
test_schema_v2_recorded_rollback_target() (
  export NIXDB_STATE_DIR="$schema_v2_state"
  export NIXDB_SYSTEM_PROFILE="$test_root/schema-v2-profile"
  source_cli "$manifest" "$rollback_repo"
  current_generation() { echo 23; }
  write_deployment_state "$test_root/schema-v2-current" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    "$(cat "$manifest")" false "$test_root/schema-v2-recorded-previous" 20 \
    bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  [[ $(jq -r .schemaVersion "$schema_v2_state/deployment-state.json") == 2 ]]
  select_rollback_target "$test_root/schema-v2-current" 23
  [[ "$previous_generation" == 20 ]]
  [[ "$previous_system" == "$test_root/schema-v2-recorded-previous" ]]
)
test_schema_v2_recorded_rollback_target || fail 'schema-v2 rollback selected an intermediate NixOS generation'
pass 'schema-v2 state writer selects its exact recorded pre-deployment generation'

fallback_state="$test_root/fallback-state"
mkdir -p "$fallback_state" \
  "$test_root/fallback-current" \
  "$test_root/fallback-old" \
  "$test_root/fallback-intermediate-21" \
  "$test_root/fallback-intermediate-22"
ln -s "$test_root/fallback-old" "$test_root/fallback-profile-20-link"
ln -s "$test_root/fallback-intermediate-21" "$test_root/fallback-profile-21-link"
ln -s "$test_root/fallback-intermediate-22" "$test_root/fallback-profile-22-link"

test_rollback_fallback() (
  export NIXDB_STATE_DIR="$fallback_state"
  export NIXDB_SYSTEM_PROFILE="$test_root/fallback-profile"
  source_cli "$manifest" "$rollback_repo"
  nix-env() {
    printf '20 old\n21 intermediate\n22 newer-intermediate\n23 current (current)\n'
  }
  select_rollback_target "$test_root/fallback-current" 23
  [[ "$previous_generation" == 22 ]]
  [[ "$previous_system" == "$test_root/fallback-intermediate-22" ]]
)

malformed_fallback_output="$test_root/malformed-fallback-output"
printf '{not-json\n' >"$fallback_state/deployment-state.json"
test_rollback_fallback >"$malformed_fallback_output" 2>&1 \
  || fail 'malformed deployment state did not use the documented fallback'
grep -F 'deployment state is malformed JSON' "$malformed_fallback_output" >/dev/null
grep -F 'falling back to previous NixOS generation' "$malformed_fallback_output" >/dev/null
pass 'malformed deployment state is never interpreted as an exact rollback target'

unknown_schema_fallback_output="$test_root/unknown-schema-fallback-output"
make_legacy_deployment_state "$fallback_state/deployment-state.json" \
  "$test_root/fallback-current" 23 "$test_root/fallback-old" 20
jq '.schemaVersion = 3' "$fallback_state/deployment-state.json" >"$fallback_state/deployment-state.next"
mv "$fallback_state/deployment-state.next" "$fallback_state/deployment-state.json"
test_rollback_fallback >"$unknown_schema_fallback_output" 2>&1 \
  || fail 'unknown deployment-state schema did not use the documented fallback'
grep -F 'unsupported schema version' "$unknown_schema_fallback_output" >/dev/null
grep -F 'falling back to previous NixOS generation' "$unknown_schema_fallback_output" >/dev/null
pass 'unknown future deployment-state schema is not interpreted as current'

missing_previous_fallback_output="$test_root/missing-previous-fallback-output"
make_legacy_deployment_state "$fallback_state/deployment-state.json" \
  "$test_root/fallback-current" 23 "$test_root/fallback-old" 20
jq 'del(.previous.generation)' "$fallback_state/deployment-state.json" >"$fallback_state/deployment-state.next"
mv "$fallback_state/deployment-state.next" "$fallback_state/deployment-state.json"
test_rollback_fallback >"$missing_previous_fallback_output" 2>&1 \
  || fail 'incomplete deployment state did not use the documented fallback'
grep -F 'deployment state is invalid or incomplete' "$missing_previous_fallback_output" >/dev/null
grep -F 'falling back to previous NixOS generation' "$missing_previous_fallback_output" >/dev/null
pass 'missing recorded previous generation has an explicit compatibility fallback'

ordinary_fallback_output="$test_root/ordinary-fallback-output"
rm -f "$fallback_state/deployment-state.json"
test_rollback_fallback >"$ordinary_fallback_output" 2>&1 \
  || fail 'absent deployment state did not use the documented fallback'
grep -F 'deployment state is absent' "$ordinary_fallback_output" >/dev/null
grep -F 'falling back to previous NixOS generation' "$ordinary_fallback_output" >/dev/null
pass 'ordinary rollback fallback selects the previous NixOS generation explicitly'

exact_db_rollback_state="$test_root/exact-db-rollback-state"
mkdir -p "$exact_db_rollback_state/generations" \
  "$test_root/exact-db-current" \
  "$test_root/exact-db-recorded-previous" \
  "$test_root/exact-db-intermediate-21" \
  "$test_root/exact-db-intermediate-22"
ln -s "$test_root/exact-db-current" "$test_root/exact-db-current-link"
ln -s "$test_root/exact-db-recorded-previous" "$test_root/exact-db-profile-20-link"
ln -s "$test_root/exact-db-intermediate-21" "$test_root/exact-db-profile-21-link"
ln -s "$test_root/exact-db-intermediate-22" "$test_root/exact-db-profile-22-link"
jq -n '{dbUpgradeOccurred:true,dbVersions:{mongodb:"8.2.12"}}' \
  >"$exact_db_rollback_state/generations/$(basename "$test_root/exact-db-current").json"
jq -n '{dbUpgradeOccurred:false,dbVersions:{mongodb:"8.2.11"}}' \
  >"$exact_db_rollback_state/generations/$(basename "$test_root/exact-db-recorded-previous").json"
test_schema_v2_db_rollback_protection() (
  export NIXDB_CURRENT_SYSTEM="$test_root/exact-db-current-link"
  export NIXDB_STATE_DIR="$exact_db_rollback_state"
  export NIXDB_SYSTEM_PROFILE="$test_root/exact-db-profile"
  source_cli "$manifest" "$rollback_repo"
  current_generation() { echo 23; }
  write_deployment_state "$test_root/exact-db-current" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    "$(cat "$manifest")" false "$test_root/exact-db-recorded-previous" 20 \
    bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  nix-env() {
    printf '20 old\n21 intermediate\n22 newer-intermediate\n23 current (current)\n'
  }
  cmd_rollback
)
exact_db_rollback_output="$test_root/exact-db-rollback-output"
if test_schema_v2_db_rollback_protection >"$exact_db_rollback_output" 2>&1; then
  fail 'exact schema-v2 DB binary rollback was not blocked'
fi
grep -F 'Target generation:   20' "$exact_db_rollback_output" >/dev/null
grep -F -- '--allow-db-binary-rollback' "$exact_db_rollback_output" >/dev/null
pass 'DB binary downgrade protection applies after exact schema-v2 target selection'

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
  runtime_redis_version() { echo 8.10.0; }
  runtime_dragonfly_version() { echo 1.40.1; }
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
  path_state_system="$test_root/path-state-system"
  mkdir -p "$path_state_system"
  ln -s "$path_state_system" "$test_root/path-state-current"
  export NIXDB_CURRENT_SYSTEM="$test_root/path-state-current"
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

signal_generation_capture="$test_root/signal-generation"
test_term_recovery() (
  local phase=$1 activation_started=$2 work=$3
  export NIXDB_CURRENT_SYSTEM="$test_root/current-system"
  source_cli "$manifest" "$failure_repo"
  tx_old_commit=$(git -C "$failure_repo" rev-parse HEAD)
  tx_old_branch=$(git -C "$failure_repo" symbolic-ref --short HEAD)
  tx_old_system=$fake_system
  tx_old_generation=7
  tx_lock_backup="$test_root/term-${activation_started}.lock"
  install -m 0600 "$failure_repo/flake.lock" "$tx_lock_backup"
  work_tmp="$work"
  mkdir -p "$work_tmp"
  touch "$work_tmp/candidate-artifact"
  deployment_phase=$phase
  tx_activation_started=$activation_started
  nix-env() {
    if [[ $1 == --switch-generation ]]; then
      printf '%s\n' "$2" >"$signal_generation_capture"
    fi
  }
  trap 'transaction_failure 143' TERM
  kill -TERM "$BASHPID"
)

before_term_lock=$(sha256sum "$failure_repo/flake.lock")
term_pre_work="$test_root/term-before-activation"
set +e
test_term_recovery 'candidate preparation' 0 "$term_pre_work" >/dev/null 2>&1
term_pre_rc=$?
set -e
((term_pre_rc == 143)) || fail "pre-activation TERM did not preserve signal exit code $term_pre_rc"
[[ ! -e "$term_pre_work" ]] || fail 'pre-activation TERM did not clean the private candidate worktree'
[[ "$before_term_lock" == "$(sha256sum "$failure_repo/flake.lock")" ]] || fail 'pre-activation TERM changed downstream flake.lock'
git -C "$failure_repo" diff --quiet || fail 'pre-activation TERM left downstream source dirty'

term_post_work="$test_root/term-after-test"
set +e
test_term_recovery 'test candidate' 1 "$term_post_work" >/dev/null 2>&1
term_post_rc=$?
set -e
((term_post_rc == 143)) || fail "post-test TERM did not preserve signal exit code $term_post_rc"
[[ ! -e "$term_post_work" ]] || fail 'post-test TERM did not clean the private candidate worktree'
[[ $(cat "$signal_generation_capture") == 7 ]] || fail 'post-test TERM did not restore the exact prior generation'
[[ "$before_term_lock" == "$(sha256sum "$failure_repo/flake.lock")" ]] || fail 'post-test TERM changed downstream flake.lock'
git -C "$failure_repo" diff --quiet || fail 'post-test TERM left downstream source dirty'
pass 'TERM recovery cleans candidate state and restores the exact generation after test'

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
