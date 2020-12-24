# Bashistrano
Script for Capistrano style deployments with Bash and rsync.

## Examples

### Deploying NodeJS application and reloading related systemd unit

```
$ export \
    BASHISTRANO_SOURCE_DIR=/home/developer/app \
    BASHISTRANO_DEST_DIR=/home/app \
    BASHISTRANO_TARGET_HOST=tests@production.local \
    BASHISTRANO_POST_COPY="npm install" \
    BASHISTRANO_POST_DEPLOY="systemctl --user restart app.service"
$ bashistrano.sh
```

## Environment variables

- BASHISTRANO_SOURCE_DIR  - directory with application to deploy
- BASHISTRANO_DEST_DIR    - destination directory
- BASHISTRANO_TARGET_HOST - target host
- BASHISTRANO_RSYNC_ARGS  - additional rsync arguments
- BASHISTRANO_SSH_ARGS    - additional ssh arguments
- BASHISTRANO_POST_COPY   - command to run after copying application,
                            but before symlinking new version
- BASHISTRANO_POST_DEPLOY - command to run after symlinking new version
- BASHISTRANO_LOG_LEVEL   - debug(1), info(2), warn(3), error(4), crit(5)
- BASHISTRANO_KEEP        - how much releases to keep

## Running tests

Tests require Podman in order to create container with SSH server.

```./tests.sh```

## About

Generating README.md:

```awk '/^#####/{flag=!flag;next}flag{sub("^..?", "");print}' bashistrano.sh > README.md```

[Source](https://github.com/local-cloud/bashistrano)
