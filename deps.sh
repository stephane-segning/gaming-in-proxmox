#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

if ! command -v apt-get >/dev/null 2>&1; then
  echo "Error: apt-get is required to install dependencies." >&2
  exit 1
fi

DEPS=(
  ca-certificates
  curl
  dpkg
  libcap2-bin
  wget
  git
)

echo "Installing dependencies: ${DEPS[*]}"
sudo apt-get update
sudo apt-get install -y "${DEPS[@]}"
echo "Done."
