#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

for script in scripts/*.sh; do
  sh -n "$script"
done

./scripts/audit.sh

echo "checks passed"
