#!/bin/sh
# Boot smoke test for the Nightlight app (add-on) config.
#
# Usage: sh scripts/smoke.sh [path/to/config.yaml]     (default: nightlight/config.yaml)
# Env:   HOST_PORT  host port to publish the app's 4000 on (default 4000; pick a free one locally)
#        KEEP=1     leave the container and volumes behind for a look (default: removed)
#
# What it proves, by running the real image the way the Home Assistant Supervisor starts it:
#   1. config.yaml's `image` has no tag of its own and `version` is a tag that exists on the registry,
#      for every architecture `arch` declares (the Supervisor pulls <image>:<version>).
#   2. `timeout` is 30 (the app needs up to 23 s to stop cleanly; the Supervisor's default is 10).
#   3. The image boots on an EMPTY, ROOT-OWNED /data with a root-owned options.json in it, using the
#      `environment` from config.yaml (parsed here, so the test follows the config), answers
#      GET /api/health with 200 and turns Docker-healthy (what the Supervisor's watchdog reads).
#   4. The database and writable recording storage land under private /data, not /app/data or /media.
#   5. It comes back after `docker restart` AND after the container is removed and created again
#      (what the Supervisor does on every restart and update) with the SAME server id, which lives in
#      the database: so /data really persisted.
#   6. A stop finishes inside `timeout` with exit code 0.
#   7. A simulated restore without the excluded clips, with restored files owned by root (as in
#      Supervisor's restore), boots with the same server id and re-owns the restored files.
#
# What it cannot prove: Home Assistant OS itself, AppArmor as the Supervisor applies it, host
# networking on a real home network, cameras, aarch64 (only the runner's architecture is booted),
# a real Home Assistant backup and restore, and a stop with a recording in progress.
#
# Docker options that copy the Supervisor (supervisor/docker/app.py and interface.py, 2026-11-21):
# seccomp=unconfined, a private tmpfs /dev/shm, no --init when `init: false`, the stop timeout, TZ set.
# It also drops AUDIT_WRITE, MKNOD, SETFCAP and NET_RAW, which the Supervisor drops only behind
# feature flags today: testing the stricter set means a future flag cannot surprise us.
# Host networking is NOT used (CI runners and Docker Desktop differ); the port is published instead.

set -eu

# Git Bash on Windows rewrites arguments that look like paths (/data -> C:/Program Files/Git/data).
# Harmless on Linux.
MSYS_NO_PATHCONV=1
export MSYS_NO_PATHCONV

CONFIG=${1:-nightlight/config.yaml}
HOST_PORT=${HOST_PORT:-4000}
KEEP=${KEEP:-}
RUN_ID="nightlight-smoke-$(date +%s)-$$"
CTR="$RUN_ID"
VOL_DATA="$RUN_ID-data"
VOL_RESTORE="$RUN_ID-restore"
# The volume start() mounts at /data: VOL_DATA, then VOL_RESTORE for the restore step.
DATA_VOL=$VOL_DATA
# The image's healthcheck has a 120 s start period; allow well past it.
HEALTH_WAIT=240

log() { printf '[smoke] %s\n' "$*"; }
fail() {
  printf '[smoke] FAIL: %s\n' "$*" >&2
  if docker inspect "$CTR" >/dev/null 2>&1; then
    printf '[smoke] last 150 log lines of %s:\n' "$CTR" >&2
    docker logs --tail 150 "$CTR" >&2 2>&1 || :
  fi
  exit 1
}

cleanup() {
  if [ -n "$KEEP" ]; then
    log "KEEP=1: leaving container $CTR and volumes $VOL_DATA $VOL_RESTORE"
    return
  fi
  # -v also removes the anonymous volume Docker makes for the image's VOLUME /app/data (unused here,
  # because DATA_DIR=/data). The Supervisor removes its containers the same way (v=True).
  docker rm -f -v "$CTR" >/dev/null 2>&1 || :
  docker volume rm "$VOL_DATA" >/dev/null 2>&1 || :
  docker volume rm "$VOL_RESTORE" >/dev/null 2>&1 || :
}
trap cleanup EXIT
trap 'exit 130' INT TERM

[ -f "$CONFIG" ] || fail "no config at $CONFIG"

# --- Reading config.yaml ---------------------------------------------------------------------------
# A deliberately small reader for the layout this repository uses (top-level `key: value`, an
# `environment:` block of `  NAME: value` lines), so the test
# needs nothing but sh and awk. The app linter in CI is what checks the file is valid YAML for the
# Supervisor; this only has to read the values back. Comments and CRLF are ignored.
top() { # top <key>: the scalar value of a top-level key, quotes removed; empty if absent
  awk -v k="$1" '
    { sub(/\r$/, "") }
    $0 ~ "^" k ":" {
      v = substr($0, length(k) + 2)
      sub(/^[ \t]+/, "", v); sub(/[ \t]+#.*$/, "", v); sub(/[ \t]+$/, "", v)
      if (v ~ /^".*"$/ || v ~ /^'"'"'.*'"'"'$/) v = substr(v, 2, length(v) - 2)
      print v; exit
    }' "$CONFIG"
}
block() { # block <key>: the indented lines under a top-level key, comments and blanks removed
  awk -v k="$1" '
    { sub(/\r$/, "") }
    $0 ~ "^" k ":[ \t]*$" { inb = 1; next }
    inb && /^[^ \t#]/ { exit }
    inb && /^[ \t]*(#|$)/ { next }
    inb { print }' "$CONFIG"
}

VERSION=$(top version)
IMAGE=$(top image)
TIMEOUT=$(top timeout)
INIT=$(top init)
HOST_NETWORK=$(top host_network)
BACKUP=$(top backup)
[ -n "$VERSION" ] || fail "config has no version"
[ -n "$IMAGE" ] || fail "config has no image"

# 1. The Supervisor pulls <image>:<version>: a tag or digest inside `image` would be wrong.
case "$IMAGE" in
  *@*) fail "image '$IMAGE' carries a digest; the Supervisor takes the tag from version" ;;
  *'{arch}'*) fail "image '$IMAGE' uses {arch}; this app relies on one multi-architecture image" ;;
esac
case "${IMAGE##*/}" in
  *:*) fail "image '$IMAGE' carries a tag; the Supervisor takes the tag from version ($VERSION)" ;;
esac
REF="$IMAGE:$VERSION"
log "config: image $REF, timeout ${TIMEOUT:-<unset>}, init ${INIT:-<default true>}"

# 2. The stop timeout.
[ "$TIMEOUT" = 30 ] || fail "timeout is '${TIMEOUT:-<unset>}', expected 30 (Nightlight needs up to 23 s to stop cleanly)"
[ "$HOST_NETWORK" = true ] || fail "host_network is '${HOST_NETWORK:-<unset>}', expected true"
[ "$BACKUP" = cold ] || fail "backup is '${BACKUP:-<unset>}', expected cold"
[ "$INIT" = false ] || fail "init is '${INIT:-<unset>}', expected false"
[ "$(awk '/^map:/ { found = 1 } END { print found + 0 }' "$CONFIG")" = 0 ] || fail "config must not map shared folders such as media"

# The architectures config.yaml promises must all be in the published image.
ARCHES=$(block arch | sed -n 's/^[[:space:]]*-[[:space:]]*//p' | tr -d '"'"'" | tr -d '\r')
[ -n "$ARCHES" ] || fail "config has no arch list"
MANIFEST=$(docker manifest inspect "$REF" 2>&1) || fail "cannot read the manifest of $REF (does the tag exist, and is the package public?): $MANIFEST"
for a in $ARCHES; do
  case "$a" in
    aarch64) d=arm64 ;;
    amd64) d=amd64 ;;
    *) fail "unexpected arch '$a' in config" ;;
  esac
  printf '%s' "$MANIFEST" | grep -q "\"architecture\": *\"$d\"" || fail "$REF has no linux/$d image, but config.yaml lists $a"
  log "registry: $REF has linux/$d"
done

# 3. The environment, exactly as config.yaml sets it.
ENV_ARGS=
ENV_LINES=$(block environment)
DATA_DIR=
OLDIFS=$IFS
IFS='
'
set -f # one line per word, and no filename globbing of what the config says
for line in $ENV_LINES; do
  name=$(printf '%s' "$line" | sed -n 's/^[[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\):.*/\1/p')
  value=$(printf '%s' "$line" | sed 's/^[^:]*:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//')
  case "$value" in \"*\") value=${value#\"}; value=${value%\"} ;; esac
  [ -n "$name" ] || fail "cannot read environment line: $line"
  # Names and values in this config are plain paths and words; refuse anything that would need quoting.
  case "$value" in *[!A-Za-z0-9_./:-]*) fail "environment $name has characters this test does not pass through: $value" ;; esac
  ENV_ARGS="$ENV_ARGS -e $name=$value"
  [ "$name" = DATA_DIR ] && DATA_DIR=$value
  [ "$name" != CLIPS_DIR ] || fail "CLIPS_DIR must be unset so recordings remain in private /data/clips"
  log "config: environment $name=$value"
done
set +f
IFS=$OLDIFS
[ "$DATA_DIR" = /data ] || fail "environment DATA_DIR is '${DATA_DIR:-<unset>}'; the Supervisor mounts the app's storage at /data"
EXCLUDED=$(block backup_exclude | sed -n 's/^[[:space:]]*-[[:space:]]*//p' | tr -d "\"'")
[ "$EXCLUDED" = clips ] || fail "backup_exclude must contain only clips, leaving the database and snapshots in backups"

# --- Volumes: empty and owned by root, as the Supervisor creates them -------------------------------
docker pull -q "$REF" >/dev/null || fail "cannot pull $REF"
docker volume create "$VOL_DATA" >/dev/null

as_root() { # as_root <shell command>: run in the image as root, with the volumes mounted, no entrypoint
  docker run --rm --entrypoint /bin/sh -v "$DATA_VOL:/data" "$REF" -c "$1"
}

BEFORE=$(as_root 'stat -c %u:%g /data; ls -A /data | wc -l')
[ "$BEFORE" = "0:0
0" ] || fail "the new /data volume is not empty and root-owned: $BEFORE"

# The Supervisor writes options.json before EVERY start: `{}` when the app has no options, as root,
# through a temporary file renamed into place, then chmod 600 (supervisor/utils/json.py
# write_json_file). The rename matters: it leaves a root-owned file even after the app has re-owned /data.
write_options() {
  as_root 'printf "{}" > /data/.options.tmp && chmod 600 /data/.options.tmp && mv -f /data/.options.tmp /data/options.json'
}

start() {
  write_options
  # shellcheck disable=SC2086 # ENV_ARGS is built above from checked words
  docker run -d --name "$CTR" \
    -p "$HOST_PORT:4000" \
    -v "$DATA_VOL:/data" \
    $ENV_ARGS -e TZ=UTC \
    --stop-timeout "$TIMEOUT" \
    --security-opt seccomp=unconfined \
    --tmpfs /dev/shm \
    --cap-drop AUDIT_WRITE --cap-drop MKNOD --cap-drop SETFCAP --cap-drop NET_RAW \
    "$REF" >/dev/null || fail "docker run failed"
}

health_id() { # waits for GET /api/health 200; prints the server id from its body
  deadline=$(($(date +%s) + HEALTH_WAIT))
  while :; do
    remaining=$((deadline - $(date +%s)))
    [ "$remaining" -gt 0 ] || fail "/api/health did not answer 200 within $HEALTH_WAIT s"
    curl_limit=$remaining
    [ "$curl_limit" -le 5 ] || curl_limit=5
    if body=$(curl -fsS --max-time "$curl_limit" "http://127.0.0.1:$HOST_PORT/api/health" 2>/dev/null); then
      [ "$(date +%s)" -le "$deadline" ] || fail "/api/health answered after the $HEALTH_WAIT s deadline"
      id=$(printf '%s' "$body" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
      [ -n "$id" ] || fail "/api/health answered without an id: $body"
      printf '%s' "$id"
      return 0
    fi
    state=$(docker inspect -f '{{.State.Status}}' "$CTR" 2>/dev/null || echo gone)
    [ "$state" = running ] || fail "container is $state before /api/health answered"
    remaining=$((deadline - $(date +%s)))
    [ "$remaining" -gt 0 ] || fail "/api/health did not answer 200 within $HEALTH_WAIT s"
    [ "$remaining" -le 2 ] && sleep "$remaining" || sleep 2
  done
}

docker_healthy() { # waits for Docker's own HEALTHCHECK to report healthy (what the watchdog reads)
  deadline=$(($(date +%s) + HEALTH_WAIT))
  while :; do
    [ "$(date +%s)" -lt "$deadline" ] || fail "Docker's healthcheck did not report healthy within $HEALTH_WAIT s"
    h=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CTR")
    case "$h" in
      healthy) [ "$(date +%s)" -le "$deadline" ] && return 0 ;;
      none) fail "the image has no HEALTHCHECK, so the Supervisor's watchdog would have nothing to read" ;;
      unhealthy) fail "Docker marked the container unhealthy" ;;
    esac
    remaining=$((deadline - $(date +%s)))
    [ "$remaining" -gt 0 ] || fail "Docker's healthcheck did not report healthy within $HEALTH_WAIT s"
    [ "$remaining" -le 2 ] && sleep "$remaining" || sleep 2
  done
}

check_layout() {
  docker exec "$CTR" test -f "$DATA_DIR/private/babymonitor.db" || fail "no database at $DATA_DIR/private/babymonitor.db"
  if docker exec "$CTR" sh -c 'test -e /app/data/babymonitor.db || test -e /app/data/private/babymonitor.db'; then
    fail "a database appeared under /app/data: DATA_DIR was not honoured"
  fi
  docker exec "$CTR" test -f "$DATA_DIR/options.json" || fail "options.json is gone from $DATA_DIR"
  docker exec "$CTR" test -d "$DATA_DIR/clips" || fail "recording storage $DATA_DIR/clips was not created"
  log "recording storage $DATA_DIR/clips exists, owner $(docker exec "$CTR" stat -c %u:%g "$DATA_DIR/clips"), mode $(docker exec "$CTR" stat -c %a "$DATA_DIR/clips")"
  # The app's start-up check writes a probe file and reports whether recording storage is usable.
  deadline=$(($(date +%s) + 60))
  while :; do
    logs=$(docker logs "$CTR" 2>&1)
    if printf '%s\n' "$logs" | grep -Eq 'CLIPS_DIR .*(not writable|NOT a mapped volume)'; then
      fail "the app cannot record into $DATA_DIR/clips"
    fi
    printf '%s\n' "$logs" | grep -Fq "[clips] storage OK at $DATA_DIR/clips" && break
    [ "$(date +%s)" -lt "$deadline" ] || fail "no '[clips] storage OK at $DATA_DIR/clips' line within 60 s of /api/health"
    sleep 2
  done
  log "the app reports recording storage OK at $DATA_DIR/clips"
}

stop_within_timeout() {
  t0=$(date +%s)
  docker stop -t "$TIMEOUT" "$CTR" >/dev/null
  t1=$(date +%s)
  code=$(docker inspect -f '{{.State.ExitCode}}' "$CTR")
  log "stop took $((t1 - t0)) s, exit code $code"
  [ "$code" = 0 ] || fail "the app stopped with exit $code instead of 0"
}

# --- First boot ----------------------------------------------------------------------------------
log "first boot of $REF on an empty, root-owned /data (port $HOST_PORT)"
start
ID1=$(health_id)
log "first boot: /api/health 200, server id $ID1"
docker_healthy
log "first boot: Docker reports healthy"
check_layout
docker logs "$CTR" 2>&1 | grep -E '^\[entrypoint\]' | sed 's/^/[smoke]   /' || :

# --- docker restart ------------------------------------------------------------------------------
log "docker restart"
docker restart -t "$TIMEOUT" "$CTR" >/dev/null
ID2=$(health_id)
[ "$ID2" = "$ID1" ] || fail "server id changed across docker restart ($ID1 -> $ID2): /data did not persist"
log "after restart: same server id"

# --- Remove and re-create, as the Supervisor does on restart and update --------------------------
log "stop, remove and re-create the container on the same /data"
stop_within_timeout
docker rm -v "$CTR" >/dev/null
start
ID3=$(health_id)
[ "$ID3" = "$ID1" ] || fail "server id changed across re-create ($ID1 -> $ID3): /data did not persist"
docker_healthy
check_layout
log "after re-create: same server id, Docker healthy"
stop_within_timeout
docker rm -v "$CTR" >/dev/null

# --- A restore, as the Supervisor does it ---------------------------------------------------------
# The Supervisor restores an app's data by extracting the backup into a temporary folder and copying
# it into place with shutil.copytree (supervisor/apps/app.py `restore`, read 2026-11-21). copytree
# keeps file modes but not owners, so every restored file, /data itself included, belongs to root.
# The backup excludes clips, so the restored copy must omit them too.
log "restore: a copy of /data without clips, with every restored file owned by root"
docker volume create "$VOL_RESTORE" >/dev/null
docker run --rm --entrypoint /bin/sh -v "$VOL_DATA:/from:ro" -v "$VOL_RESTORE:/data" "$REF" \
  -c 'for p in /from/* /from/.[!.]* /from/..?*; do [ -e "$p" ] || continue; [ "$p" = /from/clips ] && continue; cp -a "$p" /data/; done; chown -R 0:0 /data' || fail "could not make the restore copy"
DATA_VOL=$VOL_RESTORE
[ ! "$(as_root 'test -e /data/clips && echo present || echo absent')" = present ] || fail "excluded clips appeared in the restore copy"
[ "$(as_root 'find /data ! -user 0 | wc -l')" = 0 ] || fail "the restore copy still has files not owned by root"
start
ID4=$(health_id)
[ "$ID4" = "$ID1" ] || fail "server id changed after the restore ($ID1 -> $ID4): the restored database was not used"
docker logs "$CTR" 2>&1 | grep -Fq "fixing the whole data directory" || fail "the entrypoint did not re-own the restored /data"
APP_UID=$(docker exec "$CTR" id -u nightlight)
LEFT=$(docker exec "$CTR" sh -c 'find /data ! -name options.json -user 0 | wc -l')
[ "$LEFT" = 0 ] || fail "$LEFT restored entries under /data are still owned by root after the start"
log "after restore: same server id, every restored file now owned by uid $APP_UID"
docker_healthy
check_layout
stop_within_timeout

log "PASS: $REF boots, survives restart, re-create and a simulated restore, and stops within $TIMEOUT s"
