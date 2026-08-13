#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

root=${1:?usage: no-secrets.sh SOURCE_ROOT}

secret_shape='BEGIN (OPENSSH|RSA|EC|DSA) PRIVATE KEY|gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|"auths"[[:space:]]*:'
host_specific='/(home/[^/[:space:]]+|root)/|/dev/disk/by-uuid/|UUID=[0-9a-fA-F-]{32,}|(^|[^0-9])(10[.][0-9]{1,3}[.][0-9]{1,3}[.][0-9]{1,3}|192[.]168[.][0-9]{1,3}[.][0-9]{1,3}|172[.](1[6-9]|2[0-9]|3[01])[.][0-9]{1,3}[.][0-9]{1,3})([^0-9]|$)'

if grep -RInE \
  --exclude='no-secrets.sh' \
  --exclude-dir='.git' \
  --exclude-dir='result' \
  "$secret_shape|$host_specific" "$root"; then
  echo "secret-shaped or host-specific content found" >&2
  exit 1
fi

if find "$root" \
  -path "$root/.git" -prune -o \
  -type f \( \
    -name auth.json -o \
    -name cookies.txt -o \
    -name '*credential*report*' -o \
    -name '*deploy*key*' -o \
    -name hardware-configuration.nix \
  \) -print -quit | grep -q .; then
  echo "private host/auth artifact found" >&2
  exit 1
fi

if grep -RInE \
  --include='*.nix' \
  'password[[:space:]]*=' \
  "$root/examples" "$root/templates" 2>/dev/null \
  | grep -Fv '"CHANGE_ME"'; then
  echo "example/template password is not the CHANGE_ME placeholder" >&2
  exit 1
fi

if find "$root" -type l -name 'result*' -print -quit | grep -q .; then
  echo "Nix result symlink found" >&2
  exit 1
fi
