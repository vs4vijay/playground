# droppoint — Web Client Guide

Everything a frontend developer needs to build against the droppoint API.
Run instructions, the mental model, every endpoint, the sync protocol, and the
gotchas we pinned with tests.

---

## 1. What droppoint is

droppoint is a self-hosted, Pushbullet-style service: you register your
devices, then **pushes** (notes and links) flow between them. You can also
publish **channels** — public one-way feeds that any user can subscribe to
(think notification RSS).

There is no application code. The entire backend is a PostgreSQL schema
(`db/schema.sql`) served over HTTP by [PostgREST](https://postgrest.org).
Your database *is* the API:

- A table becomes a REST resource (`/pushes`, `/devices`, ...).
- URL query parameters are the query language (`?type=eq.link&order=modified.desc`).
- Foreign keys become "embeddings" (joined resources in one request).
- Authorization is **Row-Level Security** inside Postgres — there is no
  middleware, no handler code, no way to "forget a permission check" in a
  controller, because there are no controllers.

The practical consequence for you as a client author: **the API is uniform**.
Once you can list, filter, create, and sync one resource, you can do it to
all of them. There is no per-endpoint surprise to memorize.

## 2. Mental model

```
browser ──JSON over HTTP──> PostgREST ──SQL──> Postgres
                                │
                JWT `role` claim ──> SET ROLE app_user
                RLS policies     ──> only your rows, ever
```

Every request carries a JWT whose `role` claim is `app_user`. PostgREST
switches the database connection to that role; Postgres RLS policies then
silently rewrite every query to add `WHERE user_id = <your id from the token>`.
You *cannot* see another user's rows even by asking for them by id — the
database refuses, not an application layer.

Unauthenticated requests run as role `anon`: they see only public channel
listings and the register/login endpoints.

## 3. Quick start

```bash
docker compose up -d --wait     # Postgres on 127.0.0.1:5433, API on 127.0.0.1:1337
./smoke.sh                      # 23-check end-to-end verification (also usage examples)
```

- API base URL: `http://localhost:1337`
- Machine-readable OpenAPI: `GET http://localhost:1337/`
- psql (if you want to look at data): `psql "postgres://postgres@localhost:5433/droppoint"`

## 4. Conventions

| Topic | Behavior |
|---|---|
| Content type | Everything is JSON. Send `Content-Type: application/json` on writes. |
| Auth | `Authorization: Bearer <jwt>` header. Tokens expire after **7 days**; just log in again. |
| CORS | Enabled for all origins with preflight (`GET, POST, PATCH, PUT, DELETE, OPTIONS, HEAD`) — a browser app works with zero server config. |
| IDs | UUIDs everywhere (`id`, `iden`). Generate none yourself; the server fills them. |
| Server-stamped columns | `user_id` / `owner_id` are set from your token by triggers. **Never send them**; sending is harmless (overwritten) but pointless. |
| Errors | Envelope: `{"code": "P0001", "message": "...", "details": null, "hint": null}`. |

Status codes you'll actually see: `200` read, `201` created, `204` updated/deleted,
`400` bad request (validation, unknown filter), `401` no/invalid token,
`403` authenticated but RLS denied, `404` unknown resource or unknown query
parameter, `409` unique constraint (duplicate email/channel/subscription).

## 5. Authentication

Two RPC functions. Note the `p_` argument names — they are the JSON keys.

```bash
# register (also logs you in — returns a fresh token)
curl -X POST http://localhost:1337/rpc/register \
  -H 'Content-Type: application/json' \
  -d '{"p_email":"you@example.dev","p_password":"at-least-8-chars"}'
# → "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."   (JSON string, not an object)

curl -X POST http://localhost:1337/rpc/login \
  -H 'Content-Type: application/json' \
  -d '{"p_email":"you@example.dev","p_password":"at-least-8-chars"}'
```

- Passwords must be ≥ 8 chars (`400` otherwise). Emails are case-insensitive
  and unique (`409 P0001 "email already registered"`).
- Wrong credentials → `400` `"invalid credentials"` (same response for unknown
  email and wrong password).
- The token payload: `{"role":"app_user","user_id":"<uuid>","email":"...","exp":<epoch>}`.
  You can decode it client-side to learn your own `user_id` — handy for the
  subscription embeds — but never trust it for anything security-relevant;
  the server re-validates.

## 6. Resources

### 6.1 Devices

A device is anything that can send or receive pushes: laptop, phone, a
server-side script, a browser tab.

```bash
TOKEN="eyJ..."

# register this browser/client as a device — do this once after login
curl -X POST http://localhost:1337/devices \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -H 'Prefer: return=representation' \
  -d '{"name":"my laptop","type":"desktop"}'
# → 201, body: [ { "iden": "...", "name": "my laptop", "type": "desktop", ... } ]
```

- `type` ∈ `phone | desktop | browser | server | other` (default `other`).
- Send `sender_device_iden` with pushes so receivers can show where a push
  came from.
- "Remove a device" = `PATCH /devices?iden=eq.<iden>` with `{"active":false}`
  (tombstone; keeps sync history consistent). No DELETE endpoint by design.

### 6.2 Pushes

The core object.

| Field | Notes |
|---|---|
| `type` | `note` (default) or `link` |
| `title`, `body` | note content (either or both) |
| `url` | **required when `type=link`** — the DB enforces this (`400`) |
| `sender_device_iden` | optional; where it was sent from |
| `target_device_iden` | optional; pin to one of *your* devices, omit for all |
| `active` | `false` = deleted (tombstone). Never `false` on create. |
| `created`, `modified` | server clocks; `modified` is your sync cursor |

```bash
# send a note to all your devices
curl -X POST http://localhost:1337/pushes \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -H 'Prefer: return=representation' \
  -d '{"type":"note","title":"hi","body":"from laptop","sender_device_iden":"<iden>"}'

# send a link
curl -X POST http://localhost:1337/pushes \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"type":"link","title":"droppoint","url":"https://github.com/postgrest/postgrest"}'

# list active pushes, newest first
curl "http://localhost:1337/pushes?active=eq.true&order=modified.desc" \
  -H "Authorization: Bearer $TOKEN"
```

**Embedding** — get a push together with its sender device in one request:

```
GET /pushes?select=id,type,title,body,url,sender_device:devices!pushes_sender_device_iden_fkey(name,type)
```

The verbose `devices!pushes_sender_device_iden_fkey` is *required*: pushes
have two foreign keys to devices (sender and target), so PostgREST refuses
to guess (error `PGRST201` with a hint listing exactly these strings).
Copy the hint if you forget the syntax.

**Deleting** = `PATCH /pushes?id=eq.<id>` with `{"active":false}`. Keep the
row's `modified` value — tombstones are how your other clients learn a push
was deleted (see sync, below).

**Channels as feeds:** pushes currently belong to a single user. To broadcast
to followers, post a channel and have clients poll it — or wait for the
channel-push wiring if/when we add it.

### 6.3 Channels

Public, case-insensitively-unique by `name`, readable by anyone (even
unauthenticated), writable only by their owner.

```bash
curl -X POST http://localhost:1337/channels \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"name":"releases","description":"what shipped today"}'

curl http://localhost:1337/channels            # anon read — no token needed
```

`409` on duplicate name.

### 6.4 Subscriptions

Join table `(user_id, channel_iden)` — you subscribe *yourself*; there is no
"subscribe someone else".

```bash
curl -X POST http://localhost:1337/subscriptions \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"channel_iden":"<channel uuid>"}'      # 201; 409 if already subscribed

# with the channel's metadata embedded — nice for a subscriptions screen
curl "http://localhost:1337/subscriptions?select=*,channel:channels(name,description)" \
  -H "Authorization: Bearer $TOKEN"

# unsubscribe (delete by filter)
curl -X DELETE "http://localhost:1337/subscriptions?channel_iden=eq.<channel uuid>" \
  -H "Authorization: Bearer $TOKEN"           # 204
```

## 7. The sync protocol

This is the heart of a droppoint client. It mirrors Pushbullet's own
"tickle and refetch" model: everything is timestamp-driven polling.

**1. Initial load** — newest first, a page at a time:

```
GET /pushes?active=eq.true&order=modified.desc&limit=50
```

**2. Remember the watermark.** Store the **largest `modified` value you have
ever seen from the server** (the first row of any ordered response). Never
use the client's clock for this — clocks drift; the server's timestamp is
the only truth.

**3. Incremental sync** — poll, on an interval and/or when the tab regains
focus:

```
GET /pushes?modified=gte.<watermark>&order=modified.desc
```

Apply each returned row:

- `active=true` → insert/update in local state
- `active=false` → remove from local state (it's a tombstone)
- update watermark to `max(seen modified)` (if you persisted the *pre-poll*
  watermark, this survives a mid-sync crash — you'll just re-apply some rows,
  which is safe because application is idempotent by `id`)

**4. Devices sync the same way**: `GET /devices?modified=gte.<watermark>`.

**Pagination tips**

- `limit=N` caps page size (PostgREST default max applies server-side).
- `Prefer: count=exact` returns `Content-Range: 0-49/1234` — total rows when
  you need progress UI. Costs a `COUNT(*)`; don't use it on hot polling paths.
- For infinite scroll *backwards through history*, prefer keyset over offset
  (offset drifts when rows are inserted between pages):
  `GET /pushes?active=eq.true&modified=lt.<oldest_loaded>&order=modified.desc&limit=50`
- `order` is stable/repeatable; add `&limit=0` with `Prefer: count=exact` for
  a pure count request.

**Polling cadence**: poll on `visibilitychange` (tab focused) plus a relaxed
setInterval (e.g. 15–30 s) while visible, nothing while hidden. droppoint has
no rate limits in dev, but good manners scale better than hammering.

## 8. Gotchas (all pinned by `smoke.sh`)

1. **Writes with `Prefer: return=representation` return arrays**, even for a
   single row: `[ {...} ]` — take `.[0]`.
2. **Zero-row PATCH/DELETE is `204`, not `404`.** "Nothing matched" and
   "matched and updated" look identical from the status line. If you must
   know, re-fetch. (Cross-user access is also a silent 204 no-op — by design.)
3. **Embedding `devices` from `pushes` needs the FK disambiguator**
   (`devices!pushes_sender_device_iden_fkey`) — two FKs exist, PostgREST will
   not guess.
4. **401 vs 404 on hidden resources.** An unauthenticated request to a
   resource anon can't see returns `401`; an authenticated one without
   permission gets `403`/`404` depending on exposure. Don't probe existence
   via status codes; it's not a stable oracle.
5. **`user_id` / `owner_id` are stamped server-side.** Omit them on create.
6. **`modified` is server time** (timestamptz). Use it as a string cursor,
   never parse-and-compare against local clocks.
7. **Channel names are globally unique, case-insensitive** (citext) → `409`.
8. **Password rules are enforced server-side** (≥ 8 chars). Pre-validate to
   save a round trip, but handle the `400` anyway.
9. **Tokens expire in 7 days.** On a `401`, drop the token and re-login —
   there is no refresh endpoint.

## 9. Minimal JS client

A complete client core in ~40 lines. No dependencies.

```js
const API = "http://localhost:1337";

async function api(path, { method = "GET", body, token } = {}) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw Object.assign(new Error(err.message ?? res.statusText), { status: res.status, err });
  }
  return res.status === 204 ? null : res.json();
}

const auth = {
  token: null,
  async register(email, password) { this.token = await api("/rpc/register",  { method: "POST", body: { p_email: email, p_password: password } }); },
  async login(email, password)    { this.token = await api("/rpc/login",     { method: "POST", body: { p_email: email, p_password: password } }); },
};

// one-time per browser: register this client as a device
async function registerDevice(name, type = "browser") {
  const res = await fetch(`${API}/devices`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${auth.token}`, Prefer: "return=representation" },
    body: JSON.stringify({ name, type }),
  });
  return (await res.json())[0]; // representation is an array — take [0]
}

let watermark = localStorage.getItem("dp.watermark") ?? "";

async function syncPushes({ apply, remove }) {
  const q = new URLSearchParams({ order: "modified.desc" });
  if (watermark) q.set("modified", `gte.${watermark}`);
  const rows = await api(`/pushes?${q}`, { token: auth.token });
  for (const row of rows) row.active ? apply(row) : remove(row.id);
  if (rows.length) {
    watermark = rows[0].modified;                    // newest first
    localStorage.setItem("dp.watermark", watermark);
  }
}

// poll while visible
setInterval(() => document.visibilityState === "visible" && syncPushes().catch(console.error), 20000);
document.addEventListener("visibilitychange", () => document.visibilityState === "visible" && syncPushes().catch(console.error));

async function sendPush({ title, body, url, senderDeviceIden }) {
  await api("/pushes", { method: "POST", token: auth.token,
    body: { type: url ? "link" : "note", title, body, url, sender_device_iden: senderDeviceIden } });
}
```

## 10. Schema reference

```
devices        iden uuid pk · user_id · name · type phone|desktop|browser|server|other
               · active · created · modified
pushes         id uuid pk · user_id · sender_device_iden? · target_device_iden?
               · type note|link · title? · body? · url? · active · created · modified
               rule: type=link ⇒ url not null
channels       iden uuid pk · name (unique, citext) · description? · owner_id · created
subscriptions  (user_id, channel_iden) pk · created
users          (not exposed via API — id, email, password_hash, created)
```

Every user-owned table has RLS: reads and writes are silently scoped to
`user_id = <token's user_id>`. Channels: everyone reads, only the owner
updates.

## 11. Environment notes

- The stack is bound to `127.0.0.1` only. Postgres auth is `trust` and the
  JWT secret sits in `.env` — **dev-only posture**. Before exposing this
  anywhere: set a real `JWT_SECRET`, give `authenticator` a password, drop
  `POSTGRES_HOST_AUTH_METHOD`, and put TLS in front (or run behind Caddy/nginx).
- No rate limiting, no request logs. It's PostgREST + your Postgres.
- To reset all data: `docker compose down -v && docker compose up -d --wait`
  (re-runs `db/schema.sql`; the init dir is mounted read-only on purpose —
  never put loose `.sql` files in `db/init/`, the postgres entrypoint
  auto-executes them).
