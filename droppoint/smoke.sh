#!/usr/bin/env bash
# End-to-end smoke test for the droppoint API (docker compose up first).
# Usage: ./smoke.sh   (API=http://localhost:1337 ./smoke.sh to override)
set -euo pipefail

API="${API:-http://localhost:1337}"
pass=0; fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }

# $1=expected http status, $2=description, then curl args
expect_status() {
  local want="$1" desc="$2"; shift 2
  local got
  got=$(curl -s -o /dev/null -w '%{http_code}' "$@")
  if [ "$got" = "$want" ]; then ok "$desc ($got)"; else bad "$desc (want $want, got $got)"; fi
}

auth() { printf -- '-H "Authorization: Bearer %s"' "$1"; }

R=$((RANDOM))
E1="alice$R@example.dev"
E2="bob$R@example.dev"
PW="correct horse battery"

# --- auth -------------------------------------------------------------------
T1=$(curl -s -X POST "$API/rpc/register" -H 'Content-Type: application/json' \
      -d "{\"p_email\":\"$E1\",\"p_password\":\"$PW\"}" | jq -r .)
[ -n "$T1" ] && [ "$T1" != "null" ] && ok "register returns a token" || bad "register token empty"

T1L=$(curl -s -X POST "$API/rpc/login" -H 'Content-Type: application/json' \
       -d "{\"p_email\":\"$E1\",\"p_password\":\"$PW\"}" | jq -r .)
[ -n "$T1L" ] && [ "$T1L" != "null" ] && ok "login returns a token" || bad "login token empty"

expect_status 400 "login with wrong password rejected" -X POST "$API/rpc/login" \
  -H 'Content-Type: application/json' -d "{\"p_email\":\"$E1\",\"p_password\":\"wrongpass1\"}"
expect_status 400 "register with short password rejected" -X POST "$API/rpc/register" \
  -H 'Content-Type: application/json' -d "{\"p_email\":\"short$R@example.dev\",\"p_password\":\"short\"}"

# --- devices ----------------------------------------------------------------
DEV=$(curl -s -X POST "$API/devices" -H "Authorization: Bearer $T1" \
      -H 'Content-Type: application/json' -H 'Prefer: return=representation' \
      -d '{"name":"laptop","type":"desktop"}')
IDEN=$(echo "$DEV" | jq -r '.[0].iden')
[ -n "$IDEN" ] && [ "$IDEN" != "null" ] && ok "device registered" || bad "device registration failed"

# --- pushes -----------------------------------------------------------------
P1=$(curl -s -X POST "$API/pushes" -H "Authorization: Bearer $T1" \
     -H 'Content-Type: application/json' -H 'Prefer: return=representation' \
     -d "{\"type\":\"note\",\"title\":\"hi\",\"body\":\"from laptop\",\"sender_device_iden\":\"$IDEN\"}")

PID=$(echo "$P1" | jq -r '.[0].id')
[ -n "$PID" ] && [ "$PID" != "null" ] && ok "note push created" || bad "note push failed"
expect_status 201 "link push created" -X POST "$API/pushes" \
  -H "Authorization: Bearer $T1" -H 'Content-Type: application/json' \
  -d '{"type":"link","title":"droppoint","url":"https://github.com/postgrest/postgrest"}'
expect_status 400 "link without url rejected" -X POST "$API/pushes" \
  -H "Authorization: Bearer $T1" -H 'Content-Type: application/json' \
  -d '{"type":"link","title":"no url"}'
# embedded relation: push + sender device name in one request
EMB=$(curl -s "$API/pushes?select=type,title,sender_device:devices!pushes_sender_device_iden_fkey(name)&id=eq.$PID" \
      -H "Authorization: Bearer $T1")
[ "$(echo "$EMB" | jq -r '.[0].sender_device.name')" = "laptop" ] \
  && ok "embedding: push carries sender device name" || bad "embedding broken: $EMB"

# --- sync -------------------------------------------------------------------
MOD=$(echo "$P1" | jq -r '.[0].modified')
SYNC=$(curl -s "$API/pushes?modified=gte.$MOD&order=modified.desc" -H "Authorization: Bearer $T1")
[ "$(echo "$SYNC" | jq length)" -ge 1 ] && ok "sync via modified=gte returns rows" || bad "sync returned nothing"

# --- isolation --------------------------------------------------------------
T2=$(curl -s -X POST "$API/rpc/register" -H 'Content-Type: application/json' \
      -d "{\"p_email\":\"$E2\",\"p_password\":\"$PW\"}" | jq -r .)
N2=$(curl -s "$API/pushes" -H "Authorization: Bearer $T2" | jq length)
[ "$N2" = "0" ] && ok "user isolation: bob sees none of alice's pushes" || bad "RLS leak: bob sees $N2 pushes"
N2D=$(curl -s "$API/devices" -H "Authorization: Bearer $T2" | jq length)
[ "$N2D" = "0" ] && ok "user isolation: bob sees none of alice's devices" || bad "RLS leak: bob sees $N2D devices"

# --- channels ---------------------------------------------------------------
expect_status 201 "channel created" -X POST "$API/channels" \
  -H "Authorization: Bearer $T1" -H 'Content-Type: application/json' \
  -H 'Prefer: return=representation' \
  -d "{\"name\":\"rel$R\",\"description\":\"droppoint release feed\"}"
CH=$(curl -s "$API/channels?name=eq.rel$R" | jq -r '.[0].iden')

expect_status 201 "bob subscribes to channel" -X POST "$API/subscriptions" \
  -H "Authorization: Bearer $T2" -H 'Content-Type: application/json' \
  -d "{\"channel_iden\":\"$CH\"}"
expect_status 409 "duplicate subscription rejected" -X POST "$API/subscriptions" \
  -H "Authorization: Bearer $T2" -H 'Content-Type: application/json' \
  -d "{\"channel_iden\":\"$CH\"}"

# --- permission edges -------------------------------------------------------
expect_status 401 "anon blocked from pushes" "$API/pushes"
USERS_ANON=$(curl -s -o /dev/null -w '%{http_code}' "$API/users")
case "$USERS_ANON" in 401|404) ok "users hidden from anon ($USERS_ANON)";; *) bad "users exposed to anon ($USERS_ANON)";; esac
USERS_AUTH=$(curl -s -o /dev/null -w '%{http_code}' "$API/users" -H "Authorization: Bearer $T2")
case "$USERS_AUTH" in 401|403|404) ok "users hidden from app_user ($USERS_AUTH)";; *) bad "users exposed to app_user ($USERS_AUTH)";; esac

curl -s -o /dev/null -X PATCH "$API/pushes?id=eq.$PID" \
  -H "Authorization: Bearer $T2" -H 'Content-Type: application/json' -d '{"title":"hacked"}'
ROW=$(curl -s "$API/pushes?id=eq.$PID" -H "Authorization: Bearer $T1")
[ "$(echo "$ROW" | jq -r '.[0].title')" = "hi" ] \
  && ok "cross-user write blocked: alice's title unchanged" || bad "cross-user write leak: $ROW"
BOBROW=$(curl -s "$API/pushes?id=eq.$PID" -H "Authorization: Bearer $T2" | jq length)
[ "$BOBROW" = "0" ] && ok "cross-user read blocked: bob sees no row" || bad "cross-user read leak: $BOBROW rows"

# --- tombstone + sync -------------------------------------------------------
expect_status 204 "tombstone push (active=false)" -X PATCH "$API/pushes?id=eq.$PID" \
  -H "Authorization: Bearer $T1" -H 'Content-Type: application/json' -d '{"active":false}'
NOW=$(date -u +%Y-%m-%dT%H:%M:%S)
TOMB=$(curl -s --get "$API/pushes" --data-urlencode "modified=gte.$NOW" \
       -H "Authorization: Bearer $T1" | jq '[.[] | select(.id == "'"$PID"'")][0].active')
[ "$TOMB" = "false" ] && ok "tombstone visible in modified_since sync" || bad "tombstone not in sync (got: $TOMB)"

expect_status 204 "unsubscribe" -X DELETE "$API/subscriptions?channel_iden=eq.$CH" \
  -H "Authorization: Bearer $T2"

echo
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
