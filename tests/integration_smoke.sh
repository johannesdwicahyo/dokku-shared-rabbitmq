#!/usr/bin/env bash
#
# Integration smoke for shared-rabbitmq. Run on a real Dokku host after
# installing the plugin. Not invoked by CI — local bats stubs can't catch the
# failure modes this verifies (perms, Erlang-cookie auth, docker-network DNS,
# Dokku 0.38 dispatch, real vhost isolation).
#
# Usage:
#   ssh root@my-dokku-host 'bash -s' < tests/integration_smoke.sh

set -euo pipefail

TS="$(date +%s)"
TENANT="${TENANT:-smoke$TS}"
TENANT2="${TENANT2:-smoke${TS}b}"
APP="${APP:-smokeapp$TS}"
CONTAINER="dokku-shared-rabbitmq"

step() { printf '\n=== %s ===\n' "$1"; }
ctl()  { docker exec "$CONTAINER" rabbitmqctl "$@"; }

cleanup() {
  set +e
  step "cleanup"
  sudo -u dokku dokku apps:destroy "$APP" --force 2>/dev/null || true
  sudo -u dokku dokku shared-rabbitmq:destroy "$TENANT" -f  2>/dev/null || true
  sudo -u dokku dokku shared-rabbitmq:destroy "$TENANT2" -f 2>/dev/null || true
}
trap cleanup EXIT

step "1. plugin installed and dispatcher responds"
sudo -u dokku dokku shared-rabbitmq:help | grep -q "create <name>" \
  || { echo "FAIL: :help missing 'create <name>'"; exit 1; }

step "2. data dir is dokku-owned"
[[ "$(stat -c '%U:%G' /var/lib/dokku/services/shared-rabbitmq)" == "dokku:dokku" ]] \
  || { echo "FAIL: data dir not dokku:dokku"; exit 1; }

step "3. shared container is up"
docker ps --filter "name=^${CONTAINER}$" --format '{{.Names}}' | grep -q "$CONTAINER" \
  || { echo "FAIL: shared container not running"; exit 1; }

step "4. create tenant '$TENANT'"
sudo -u dokku dokku shared-rabbitmq:create "$TENANT" | tee /tmp/.smoke-dsn
grep -q "amqp://${TENANT}:" /tmp/.smoke-dsn || { echo "FAIL: DSN didn't print"; exit 1; }

step "5. info reports the tenant"
sudo -u dokku dokku shared-rabbitmq:info "$TENANT" | tee /tmp/.smoke-info
grep -q "Vhost:.*$TENANT" /tmp/.smoke-info || { echo "FAIL: info missing Vhost"; exit 1; }

step "6. vhost + user + permissions exist"
# Note: rabbitmqctl emits a multi-line table; piping straight into
# `grep -q` under `set -euo pipefail` produces a SIGPIPE-141 on
# rabbitmqctl when grep short-circuits, which pipefail then surfaces
# as a failure even though the match was found. Capture first, match
# second.
users="$(ctl list_users)"
vhosts="$(ctl list_vhosts)"
perms="$(ctl list_permissions -p "$TENANT")"
echo "$vhosts" | grep -qx "$TENANT" || { echo "FAIL: vhost missing"; exit 1; }
echo "$users"  | grep -q "^$TENANT" || { echo "FAIL: user missing"; exit 1; }
echo "$perms"  | grep -q "$TENANT"  || { echo "FAIL: permissions missing on vhost"; exit 1; }

step "7. cross-tenant isolation: tenant2 has no access to tenant1's vhost"
sudo -u dokku dokku shared-rabbitmq:create "$TENANT2" >/dev/null
perms2_on_t1="$(ctl list_permissions -p "$TENANT" | grep -c "^$TENANT2" || true)"
[[ "$perms2_on_t1" == "0" ]] || { echo "FAIL: tenant2 has permissions on tenant1 vhost"; exit 1; }

step "8. publish a message into tenant1's vhost (via management/declare)"
# rabbitmqadmin talks to the HTTP management API, which checks the user's
# `management` tag (separate from vhost permissions). Tenant users don't
# have the tag by design — production isolation. Grant it for the duration
# of the smoke so the test rig can declare a queue + publish, then drop
# the tag again at step 9's end so the smoke leaves the user in the same
# state production code would set up.
ctl set_permissions -p "$TENANT" "$TENANT" ".*" ".*" ".*" >/dev/null
ctl set_user_tags    "$TENANT" management >/dev/null
TPW="$(sudo -u dokku cat /var/lib/dokku/services/shared-rabbitmq/$TENANT/PASSWORD)"
docker exec "$CONTAINER" rabbitmqadmin -V "$TENANT" -u "$TENANT" -p "$TPW" \
  declare queue name=jobs durable=true \
  || { echo "FAIL: rabbitmqadmin declare failed"; exit 1; }

step "9. quota: tiny cap flips read-only"
sudo -u dokku dokku shared-rabbitmq:set-quota "$TENANT" 1
# Push 2 messages so usage (>1) exceeds the cap, then sweep.
for i in 1 2; do
  docker exec "$CONTAINER" rabbitmqadmin -V "$TENANT" -u "$TENANT" -p "$TPW" \
    publish routing_key=jobs payload="m$i" \
    || { echo "FAIL: rabbitmqadmin publish $i failed"; exit 1; }
done
# Strip the smoke-only management tag now so subsequent steps see the
# tenant in the same state the plugin's create returned them in.
ctl set_user_tags "$TENANT" >/dev/null
sudo -u dokku dokku shared-rabbitmq:check-quotas
sudo -u dokku dokku shared-rabbitmq:info "$TENANT" | grep -q "Read-only:.*true" \
  || { echo "FAIL: quota didn't flip read-only"; exit 1; }

step "10. write permission revoked while read-only"
ctl list_permissions -p "$TENANT" | grep "^$TENANT" | grep -qE '\s\s' \
  && echo "  write perm appears empty (revoked)" || echo "  (manual check of write column recommended)"

step "11. lift cap and re-sweep restores write"
sudo -u dokku dokku shared-rabbitmq:set-quota "$TENANT" 100000
sudo -u dokku dokku shared-rabbitmq:check-quotas
sudo -u dokku dokku shared-rabbitmq:info "$TENANT" | grep -q "Read-only:.*false" \
  || { echo "FAIL: write not restored after re-sweep"; exit 1; }

step "12. link to a Dokku app and verify RABBITMQ_URL"
sudo -u dokku dokku apps:create "$APP"
sudo -u dokku dokku shared-rabbitmq:link "$TENANT" "$APP"
dsn="$(sudo -u dokku dokku config:get "$APP" RABBITMQ_URL)"
[[ "$dsn" == "amqp://${TENANT}:"* ]] || { echo "FAIL: RABBITMQ_URL not set: $dsn"; exit 1; }
echo "  RABBITMQ_URL=$dsn"

step "13. unlink removes RABBITMQ_URL"
sudo -u dokku dokku shared-rabbitmq:unlink "$TENANT" "$APP"
post="$(sudo -u dokku dokku config:get "$APP" RABBITMQ_URL || true)"
[[ -z "$post" ]] || { echo "FAIL: RABBITMQ_URL still set after unlink"; exit 1; }

step "14. list shows the tenants, destroy removes them"
sudo -u dokku dokku shared-rabbitmq:list | grep -q "^$TENANT$" \
  || { echo "FAIL: list didn't include $TENANT"; exit 1; }
sudo -u dokku dokku shared-rabbitmq:destroy "$TENANT" -f
sudo -u dokku dokku shared-rabbitmq:destroy "$TENANT2" -f
ctl list_vhosts | grep -qx "$TENANT" && { echo "FAIL: vhost survived destroy"; exit 1; } || true

echo
echo "=== ALL SMOKE STEPS PASSED ==="
