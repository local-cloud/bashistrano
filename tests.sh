#!/usr/bin/env bash

set -euo pipefail

BATS="$(realpath .bats)/bin/bats"
[ ! -d .bats ] && git clone --depth 1 https://github.com/bats-core/bats-core .bats
shellcheck bashistrano.sh
"$BATS" "$@" tests
