#!/usr/bin/env bash
# End-to-end test of the whole system: the control plane from docker-compose.yml,
# and a stock Zentinel proxy managed by zentinel-cp-agent. Everything is driven
# through the public API, as a user or a CI pipeline would.
#
#   test/stack/run.sh        build, start, test, and tear down
#   KEEP=1 test/stack/run.sh leave the stack running afterwards
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
WORK=$(mktemp -d)
cd "$ROOT"

cat > "$WORK/.env" <<ENV
SECRET_KEY_BASE=$(openssl rand -base64 48 | tr -d '\n')
ENCRYPTION_KEY=$(openssl rand -base64 32 | tr -d '\n')
POSTGRES_PASSWORD=$(openssl rand -hex 16)
STORAGE_ACCESS_KEY=zentinel
STORAGE_SECRET_KEY=$(openssl rand -hex 16)
ADMIN_EMAIL=admin@example.com
ADMIN_PASSWORD=stack-test-admin-password
ZCP_URL=http://app:4000
ZCP_PROJECT=e2e
ENV

export ZCP_REGISTRATION_TOKEN=not-yet-created
C=(docker compose --env-file "$WORK/.env" -p zcp-stack-test
   -f docker-compose.yml -f agent/docker-compose.example.yml -f "$HERE/override.yml")
API=http://127.0.0.1:4000/api/v1

cleanup() {
  if [ "${KEEP:-0}" != 1 ]; then "${C[@]}" down -v >/dev/null 2>&1; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

step() { echo; echo "== $*"; }
fail() {
  echo "FAIL: $*"
  for s in app agent proxy; do echo "--- $s"; "${C[@]}" logs --tail 40 $s 2>&1 | cut -c1-240; done
  exit 1
}
http_code() { curl -s -o /dev/null -w '%{http_code}' "$1"; }

step "build and start the control plane"
"${C[@]}" build app agent || fail "build failed"
"${C[@]}" up -d postgres storage storage-init app || fail "start failed"
for i in $(seq 1 90); do
  [ "$("${C[@]}" ps app --format '{{.Health}}')" = healthy ] && break; sleep 2
done
[ "$("${C[@]}" ps app --format '{{.Health}}')" = healthy ] || fail "control plane not healthy"

step "API key and project, as the admin created on first boot"
KEY=$("${C[@]}" exec -T app bin/zentinel_cp rpc '
  u = ZentinelCp.Accounts.get_user_by_email("admin@example.com")
  [{org, _} | _] = ZentinelCp.Orgs.list_user_orgs(u.id)
  {:ok, _} = ZentinelCp.Projects.create_project(%{name: "e2e", org_id: org.id})
  {:ok, k} = ZentinelCp.Accounts.create_api_key(%{name: "e2e", user_id: u.id, scopes: []})
  IO.puts("KEY=" <> k.key)' 2>&1 | grep '^KEY=' | cut -d= -f2)
[ -n "$KEY" ] || fail "could not create an API key"
AUTH="Authorization: Bearer $KEY"

step "registration token"
ZCP_REGISTRATION_TOKEN=$(curl -sf -X POST -H "$AUTH" $API/projects/e2e/nodes/registration-token | jq -r .registration_token)
[ -n "$ZCP_REGISTRATION_TOKEN" ] && [ "$ZCP_REGISTRATION_TOKEN" != null ] || fail "no registration token"
export ZCP_REGISTRATION_TOKEN

step "start the agent; the proxy waits for its first config"
"${C[@]}" up -d agent || fail "agent did not start"
for i in $(seq 1 30); do
  N=$(curl -sf -H "$AUTH" $API/projects/e2e/nodes | jq '.nodes | length'); [ "${N:-0}" -ge 1 ] && break; sleep 2
done
[ "${N:-0}" -ge 1 ] || fail "node did not register"

deploy() {
  local version=$1 file=$2 body bundle state rollout rid rstate
  body=$(jq -n --arg v "$version" --rawfile c "$file" '{version: $v, config_source: $c}')
  bundle=$(curl -sf -X POST -H "$AUTH" -H 'content-type: application/json' -d "$body" $API/projects/e2e/bundles | jq -r .id)
  [ -n "$bundle" ] && [ "$bundle" != null ] || fail "bundle $version not created"
  for i in $(seq 1 60); do
    state=$(curl -sf -H "$AUTH" $API/projects/e2e/bundles/$bundle | jq -r '.bundle.status // .status')
    [ "$state" = compiled ] && break
    [ "$state" = failed ] && fail "bundle $version failed to compile"
    sleep 2
  done
  [ "$state" = compiled ] || fail "bundle $version not compiled"
  echo "bundle $version compiled"

  rollout=$(curl -sf -X POST -H "$AUTH" -H 'content-type: application/json' -d "{\"bundle_id\":\"$bundle\"}" $API/projects/e2e/rollouts)
  rid=$(echo "$rollout" | jq -r .id)
  for i in $(seq 1 90); do
    rstate=$(curl -sf -H "$AUTH" $API/projects/e2e/rollouts/$rid | jq -r '.rollout.state // .state')
    [ "$rstate" = completed ] && break
    case $rstate in failed|cancelled|paused) fail "rollout $version ended $rstate";; esac
    sleep 2
  done
  [ "$rstate" = completed ] || fail "rollout $version did not complete (state $rstate)"
  echo "rollout $version completed"
}

proxy_pid() {
  "${C[@]}" exec -T agent sh -c 'for p in /proc/[0-9]*; do [ "$(cat $p/comm 2>/dev/null)" = zentinel ] && basename $p; done' | head -1
}

step "release 1: the proxy starts with the first bundle"
deploy 1.0.0 "$HERE/release-1.kdl"
"${C[@]}" up -d proxy || fail "proxy did not start"
for i in $(seq 1 30); do [ "$(http_code http://127.0.0.1:18080/release-1)" = 200 ] && break; sleep 1; done
[ "$(http_code http://127.0.0.1:18080/release-1)" = 200 ] || fail "proxy does not serve release 1"
echo "proxy serves release 1"

step "release 2: the proxy reloads in place"
before=$(proxy_pid)
deploy 2.0.0 "$HERE/release-2.kdl"
for i in $(seq 1 30); do [ "$(http_code http://127.0.0.1:18080/release-2)" = 200 ] && break; sleep 1; done
[ "$(http_code http://127.0.0.1:18080/release-2)" = 200 ] || fail "proxy does not serve release 2"
[ "$(http_code http://127.0.0.1:18080/release-1)" = 404 ] || fail "proxy still serves release 1"
[ "$(proxy_pid)" = "$before" ] || fail "proxy restarted instead of reloading"
echo "proxy serves release 2, reloaded in place"

step "an invalid config is rejected and the proxy keeps serving"
body=$(jq -n '{version: "3.0.0-invalid", config_source: "routes {\n  route \"broken\" {\n    builtin-handler \"no-such-handler\"\n  }\n}\n"}')
bad=$(curl -sf -X POST -H "$AUTH" -H 'content-type: application/json' -d "$body" $API/projects/e2e/bundles | jq -r .id)
for i in $(seq 1 30); do
  state=$(curl -sf -H "$AUTH" $API/projects/e2e/bundles/$bad | jq -r '.bundle.status // .status'); [ "$state" = failed ] && break; sleep 2
done
[ "$state" = failed ] || fail "invalid config was not rejected"
[ "$(http_code http://127.0.0.1:18080/release-2)" = 200 ] || fail "proxy stopped serving"
echo "invalid config rejected"

step "node state and events"
NODE=$(curl -sf -H "$AUTH" $API/projects/e2e/nodes | jq -c '.nodes[0]')
[ "$(echo "$NODE" | jq -r .active_bundle_id)" != null ] || fail "node reports no active bundle"
EVENTS=$("${C[@]}" exec -T app bin/zentinel_cp rpc '
  for e <- ZentinelCp.Repo.all(ZentinelCp.Nodes.NodeEvent), do: IO.puts("EVENT #{e.event_type}: #{e.message}")' 2>&1 | grep '^EVENT')
echo "$EVENTS"
[ "$(echo "$EVENTS" | grep -c bundle_switch)" -ge 2 ] || fail "installs were not reported"

echo; echo "STACK TEST PASSED"
