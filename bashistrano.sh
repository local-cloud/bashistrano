#!/usr/bin/env bash
################################################################################
# # Bashistrano
# Script for Capistrano style deployments with Bash and rsync.
#
# ## Examples
#
# ### Deploying NodeJS application and reloading related systemd unit
#
# ```
# $ export \
#     BASHISTRANO_SOURCE_DIR=/home/developer/app \
#     BASHISTRANO_DEST_DIR=/home/app \
#     BASHISTRANO_TARGET_HOST=tests@production.local \
#     BASHISTRANO_POST_COPY="npm install" \
#     BASHISTRANO_POST_DEPLOY="systemctl --user restart app.service"
# $ bashistrano.sh
# ```
#
# ## Environment variables
#
# - BASHISTRANO_SOURCE_DIR  - directory with application to deploy
# - BASHISTRANO_DEST_DIR    - destination directory
# - BASHISTRANO_TARGET_HOST - target host
# - BASHISTRANO_RSYNC_ARGS  - additional rsync arguments
# - BASHISTRANO_SSH_ARGS    - additional ssh arguments
# - BASHISTRANO_POST_COPY   - command to run after copying application,
#                             but before symlinking new version
# - BASHISTRANO_POST_DEPLOY - command to run after symlinking new version
# - BASHISTRANO_LOG_LEVEL   - debug(1), info(2), warn(3), error(4), crit(5)
# - BASHISTRANO_KEEP        - how much releases to keep
#
# ## Running tests
#
# Tests require Podman in order to create container with SSH server.
#
# ```./tests.sh```
#
# ## About
#
# Generating README.md:
#
# ```awk '/^#####/{flag=!flag;next}flag{sub("^..?", "");print}' bashistrano.sh > README.md```
#
# [Source](https://github.com/local-cloud/bashistrano)
################################################################################

set -o errexit
set -o nounset
set -o pipefail

BASHISTRANO_SOURCE_DIR=${BASHISTRANO_SOURCE_DIR:?"Missing source directory"}
BASHISTRANO_DEST_DIR=${BASHISTRANO_DEST_DIR:?"Missing destination directory"}
BASHISTRANO_TARGET_HOST=${BASHISTRANO_TARGET_HOST:?"Missing target host"}
BASHISTRANO_RSYNC_ARGS=${BASHISTRANO_RSYNC_ARGS:-""}
BASHISTRANO_SSH_ARGS=${BASHISTRANO_SSH_ARGS:-""}
BASHISTRANO_POST_COPY=${BASHISTRANO_POST_COPY:-""}
BASHISTRANO_POST_DEPLOY=${BASHISTRANO_POST_DEPLOY:-""}
BASHISTRANO_LOG_LEVEL=${BASHISTRANO_LOG_LEVEL:-2}
BASHISTRANO_KEEP=${BASHISTRANO_KEEP:-3}

on_exit() {
  local exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    echo "Aborting with exit code: ${exit_code}!" >&2
  fi
  exit "$exit_code"
}

log() {
  local msg="${1}"
  local level=${2:-1}
  local output=${3:-"stdout"}
  if [ "$level" -ge "$BASHISTRANO_LOG_LEVEL" ]; then
    case "$output" in
      stdout)
        echo "$msg"
        ;;
      stderr)
        echo "$msg" >&2
        ;;
      *)
        echo "Wrong output: ${output}" >&2
        exit 1
        ;;
    esac
  fi
}

ssh_cmd() {
  if [ 1 -ge "$BASHISTRANO_LOG_LEVEL" ]; then
    echo "Running SSH command: " "$@" >&2
  fi
  local cmd args
  cmd=("$@")
  eval set -- "$BASHISTRANO_SSH_ARGS"
  args=("$@")
  # shellcheck disable=SC2086
  ssh "${args[@]}" "$BASHISTRANO_TARGET_HOST" -- "${cmd[@]}" </dev/null
}

check_dependencies() {
  log "Checking dependencies"
  for cmd in ssh rsync; do
    command -v "$cmd" >/dev/null || {
      log "Dependency ${cmd} is missing." 5 stderr
      exit 1
    }
  done
}

main() {
  trap on_exit EXIT
  export BASHISTRANO_LOG_LEVEL
  check_dependencies
  log "Creating directory structure for deployment"
  ssh_cmd mkdir -p "${BASHISTRANO_DEST_DIR}/releases"
  log "Getting last release number..."
  local current_release next_release all_releases
  all_releases=$(ssh_cmd ls -1 "${BASHISTRANO_DEST_DIR}/releases" | sort -n)
  current_release=$(echo "$all_releases" | tail -n 1)
  if echo "$current_release" | grep -qE '^[0-9]+$'; then
    next_release=$(("$current_release" + 1))
  else
    next_release=1
  fi
  log "Deploying release number ${next_release}" 2
  ssh_cmd mkdir "${BASHISTRANO_DEST_DIR}/releases/${next_release}"
  if [ 1 -ge "$BASHISTRANO_LOG_LEVEL" ]; then
    BASHISTRANO_RSYNC_ARGS="${BASHISTRANO_RSYNC_ARGS} -v"
  fi
  eval set -- "$BASHISTRANO_RSYNC_ARGS"
  rsync -a \
    "$@" \
    "$BASHISTRANO_SOURCE_DIR"/ \
    "${BASHISTRANO_TARGET_HOST}:${BASHISTRANO_DEST_DIR}/releases/${next_release}"/
  if [ -n "$BASHISTRANO_POST_COPY" ]; then
    log "Running post copy hook" 2
    eval set -- "$BASHISTRANO_POST_COPY"
    ssh_cmd \
      cd "${BASHISTRANO_DEST_DIR}/releases/${next_release}" \
      "&&" "$@"
  fi
  log "Linking directory with current version" 2
  ssh_cmd ln -Tsf \
    "${BASHISTRANO_DEST_DIR}/releases/${next_release}" \
    "${BASHISTRANO_DEST_DIR}/current"
  if [ -n "$BASHISTRANO_POST_DEPLOY" ]; then
    log "Running post deployment hook" 2
    eval set -- "$BASHISTRANO_POST_DEPLOY"
    ssh_cmd \
      cd "${BASHISTRANO_DEST_DIR}/releases/${next_release}" \
      "&&" "$@"
  fi
  local old_releases old_release
  old_releases=$(
    echo "$all_releases" \
    | sort -rn \
    | tail -n "+${BASHISTRANO_KEEP}"
  )
  echo "$old_releases" \
  | while read -r old_release; do
    [ -z "$old_release" ] && continue
    log "Removing outdated release ${old_release}" 2
    ssh_cmd rm -rf "${BASHISTRANO_DEST_DIR}/releases/${old_release}"
  done
  log "Finished deployment" 2
}

main "$@"
