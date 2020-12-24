setup_file() {
  mkdir "${BATS_RUN_TMPDIR}/keys"
  ssh-keygen -t rsa -N "" -C "bashistrano-tests" -f "${BATS_RUN_TMPDIR}/keys/id_rsa"
  podman run \
    -d --name bashistrano-tests --rm \
    -v "${BATS_RUN_TMPDIR}/keys/id_rsa.pub:/etc/authorized_keys/tests:ro" \
    -p 127.0.0.1:2222:22 \
    -e "SSH_USERS=tests:$(id -u):$(id -g):/bin/bash" \
    panubo/sshd:1.3.0
  while true; do
    local banner_length
    banner_length=$(echo "" | nc -w 3 127.0.0.1 2222 | wc -l)
    sleep 1
    [ "$banner_length" -gt 0 ] && break
  done
}

teardown_file() {
  podman rm -f bashistrano-tests
}

ssh_cmd() {
  ssh $SSH_ARGS tests@127.0.0.1 -- "$@"
}

setup() {
  local tmpdir ssh_args
  tmpdir=$(printf "%q" "$BATS_RUN_TMPDIR")
  export SSH_ARGS="-i ${tmpdir}/keys/id_rsa -p 2222 -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oLogLevel=QUIET"
  export \
    BASHISTRANO="${BATS_TEST_DIRNAME}/../bashistrano.sh" \
    BASHISTRANO_TARGET_HOST="tests@127.0.0.1" \
    BASHISTRANO_DEST_DIR="/home/tests/app" \
    BASHISTRANO_SOURCE_DIR="${BATS_TEST_DIRNAME}/app" \
    BASHISTRANO_RSYNC_ARGS="-e \"ssh ${SSH_ARGS}\"" \
    BASHISTRANO_SSH_ARGS=$SSH_ARGS \
    BASHISTRANO_KEEP=2 \
    BASHISTRANO_LOG_LEVEL=0
  unset BASHISTRANO_POST_COPY BASHISTRANO_POST_DEPLOY
  ssh_cmd rm -rf "${BASHISTRANO_DEST_DIR}"
}

@test "first deployment" {
  "$BASHISTRANO"
  run ssh_cmd cat "${BASHISTRANO_DEST_DIR}/current/constant.txt"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "constant file" ] 
}

@test "changed file" {
  echo "run 1" > "${BATS_TEST_DIRNAME}/app/changing.txt"
  "$BASHISTRANO"
  run ssh_cmd cat "${BASHISTRANO_DEST_DIR}/current/changing.txt"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "run 1" ]

  echo "run 2" > "${BATS_TEST_DIRNAME}/app/changing.txt"
  "$BASHISTRANO"
  run ssh_cmd cat "${BASHISTRANO_DEST_DIR}/current/changing.txt"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "run 2" ]
}

@test "release management" {
  for i in $(seq 3); do
    echo "run ${i}" > "${BATS_TEST_DIRNAME}/app/changing.txt"
    "$BASHISTRANO"
  done

  run ssh_cmd ls -1 "${BASHISTRANO_DEST_DIR}/releases"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l)" -eq 2 ]

  run ssh_cmd stat "${BASHISTRANO_DEST_DIR}/releases/1"
  [ "$status" -ne 0 ]

  run ssh_cmd readlink "${BASHISTRANO_DEST_DIR}/current"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "${BASHISTRANO_DEST_DIR}/releases/3" ]

  run ssh_cmd cat "${BASHISTRANO_DEST_DIR}/current/changing.txt"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "run 3" ]
}

@test "post hooks" {
  export \
    BASHISTRANO_POST_COPY="echo copy > post_hooks" \
    BASHISTRANO_POST_DEPLOY="echo deploy >> post_hooks"
  "$BASHISTRANO"
  run ssh_cmd cat "${BASHISTRANO_DEST_DIR}/current/post_hooks"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "copy" ]
  [ "${lines[1]}" = "deploy" ]
}
