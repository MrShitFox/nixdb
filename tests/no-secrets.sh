#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

root=${1:?usage: no-secrets.sh SOURCE_ROOT}

forbidden_identity='database''vm|vm''nus|192[.]168[.]1[.]41|nixdb-credentials-[0-9]|nixdb-github-deploy|by-uuid'
secret_shape='BEGIN (OPENSSH|RSA|EC|DSA) PRIVATE KEY|gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|"auths"[[:space:]]*:'

if grep -RInE \
  --exclude='no-secrets.sh' \
  --exclude-dir='.git' \
  --exclude-dir='result' \
  "$forbidden_identity|$secret_shape" "$root"; then
  echo "forbidden production identity or secret-shaped content found" >&2
  exit 1
fi

if find "$root" -type l -name 'result*' -print -quit | grep -q .; then
  echo "Nix result symlink found" >&2
  exit 1
fi
