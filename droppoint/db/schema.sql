-- droppoint: Pushbullet-style device-to-device push service
-- Entire backend is this schema + PostgREST. No application code.
--
-- Data model: users -> devices / pushes / channels / subscriptions.
-- Authorization: Postgres RLS keyed on JWT claims. PostgREST switches to
-- the role named in the token's `role` claim; policies scope every table
-- to rows where user_id = the token's user_id claim.
-- Sync protocol: rows carry server-maintained `modified` timestamps;
-- clients poll GET /pushes?modified=gte.<last_seen>&order=modified.desc.
-- Deletes are tombstones (PATCH active=false) so sync can see them.

begin;

create extension if not exists pgcrypto;  -- crypt/gen_salt/hmac for auth + JWT
create extension if not exists citext;    -- case-insensitive emails

-- ----------------------------------------------------------------------------
-- Roles. PostgREST connects as `authenticator` and SET ROLEs to anon/app_user
-- per request based on the JWT `role` claim.
-- ----------------------------------------------------------------------------
create role anon nologin;              -- unauthenticated requests
create role app_user nologin;          -- any authenticated user; RLS scopes rows
create role authenticator login password 'authenticator';
grant anon, app_user to authenticator;

create schema api;
grant usage on schema api to anon, app_user;

-- JWT signing secret shared with PostgREST (injected via 10-init.sh).
create schema private;
create table private.config (
  jwt_secret text not null
);
insert into private.config values (:'jwt_secret');

-- ----------------------------------------------------------------------------
-- Tables
-- ----------------------------------------------------------------------------
create table api.users (
  id            uuid primary key default gen_random_uuid(),
  email         citext not null unique,
  password_hash text not null,
  created       timestamptz not null default now()
);
-- No grants on api.users: invisible through the API, touched only by RPCs.

create table api.devices (
  iden     uuid primary key default gen_random_uuid(),
  user_id  uuid not null references api.users(id) on delete cascade,
  name     text not null,
  type     text not null default 'other'
           check (type in ('phone','desktop','browser','server','other')),
  active   boolean not null default true,
  created  timestamptz not null default now(),
  modified timestamptz not null default now()
);

create table api.pushes (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references api.users(id) on delete cascade,
  sender_device_iden uuid references api.devices(iden) on delete set null,
  target_device_iden uuid references api.devices(iden) on delete set null,
  type               text not null default 'note' check (type in ('note','link')),
  title              text,
  body               text,
  url                text,
  active             boolean not null default true, -- false = tombstone
  created            timestamptz not null default now(),
  modified           timestamptz not null default now(),
  constraint push_link_needs_url check (type <> 'link' or url is not null)
);

create table api.channels (
  iden        uuid primary key default gen_random_uuid(),
  name        citext not null unique, -- public handle, shareable
  description text,
  owner_id    uuid not null references api.users(id) on delete cascade,
  created     timestamptz not null default now()
);

create table api.subscriptions (
  user_id     uuid not null references api.users(id) on delete cascade,
  channel_iden uuid not null references api.channels(iden) on delete cascade,
  created     timestamptz not null default now(),
  primary key (user_id, channel_iden)
);

create index pushes_sync_idx  on api.pushes (user_id, modified desc);
create index devices_user_idx on api.devices (user_id);
create index subs_user_idx    on api.subscriptions (user_id);

-- ----------------------------------------------------------------------------
-- JWT helpers. HS256 signing in pure SQL; secret never leaves the database.
-- ----------------------------------------------------------------------------
create function api.b64url(b bytea) returns text
language sql immutable as $$
  select rtrim(translate(encode(b, 'base64'), E'+/\n', '-_'), '=')
$$;

-- Resolves the user_id claim of the current request, null when unauthenticated.
create function api.auth_uid() returns uuid
language plpgsql stable set search_path = '' as $$
declare
  v_claims text;
begin
  v_claims := coalesce(
    nullif(current_setting('request.jwt.claim.user_id', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')
  );
  if v_claims is null then
    return null;
  end if;
  return (v_claims::jsonb ->> 'user_id')::uuid;
exception when others then
  return null; -- malformed claims fail closed: RLS denies everything
end $$;

create function api.jwt_sign(payload jsonb) returns text
language sql stable security definer set search_path = '' as $$
  with parts as (
    select api.b64url(convert_to('{"alg":"HS256","typ":"JWT"}', 'utf8')) as h,
           api.b64url(convert_to(payload::text, 'utf8'))                as p
  )
  select h || '.' || p || '.' ||
         api.b64url(public.hmac(convert_to(h || '.' || p, 'utf8'),
                                convert_to(c.jwt_secret, 'utf8'), 'sha256'))
  from parts, private.config c limit 1
$$;

-- ----------------------------------------------------------------------------
-- Auth RPCs (PostgREST: POST /rpc/register, POST /rpc/login)
-- ----------------------------------------------------------------------------
create function api.register(p_email text, p_password text) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if p_password is null or length(p_password) < 8 then
    raise exception 'password must be at least 8 characters'
      using errcode = 'P0001';
  end if;
  if p_email is null or p_email !~* '[^@]+@[^@]+' then
    raise exception 'invalid email' using errcode = 'P0001';
  end if;

  insert into api.users (email, password_hash)
  values (p_email, public.crypt(p_password, public.gen_salt('bf')))
  returning id into v_id;

  return api.jwt_sign(jsonb_build_object(
    'role', 'app_user',
    'user_id', v_id,
    'email', p_email::text,
    'exp', extract(epoch from now() + interval '7 days')::bigint));
exception
  when unique_violation then
    raise exception 'email already registered' using errcode = 'P0001';
end $$;

create function api.login(p_email text, p_password text) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_user api.users;
begin
  select * into v_user from api.users where email = p_email;
  if not found
     or v_user.password_hash <> public.crypt(p_password, v_user.password_hash) then
    raise exception 'invalid credentials' using errcode = 'P0001';
  end if;
  return api.jwt_sign(jsonb_build_object(
    'role', 'app_user',
    'user_id', v_user.id,
    'email', v_user.email::text,
    'exp', extract(epoch from now() + interval '7 days')::bigint));
end $$;

grant execute on function api.register(text, text), api.login(text, text)
  to anon, app_user;

-- ----------------------------------------------------------------------------
-- Triggers: ownership stamping + modified timestamps
-- ----------------------------------------------------------------------------
create function api.stamp_owner() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_table_name = 'channels' then
    new.owner_id := api.auth_uid();
  else
    new.user_id := api.auth_uid();
  end if;
  return new;
end $$;

create trigger stamp_devices before insert on api.devices
  for each row execute function api.stamp_owner();
create trigger stamp_pushes before insert on api.pushes
  for each row execute function api.stamp_owner();
create trigger stamp_subs before insert on api.subscriptions
  for each row execute function api.stamp_owner();
create trigger stamp_channels before insert on api.channels
  for each row execute function api.stamp_owner();

create function api.touch_modified() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.modified := now();
  return new;
end $$;

create trigger touch_devices before update on api.devices
  for each row execute function api.touch_modified();
create trigger touch_pushes before update on api.pushes
  for each row execute function api.touch_modified();

-- ----------------------------------------------------------------------------
-- Row-Level Security: the entire authorization model
-- ----------------------------------------------------------------------------
alter table api.devices enable row level security;
create policy devices_crud on api.devices for all to app_user
  using (user_id = api.auth_uid())
  with check (user_id = api.auth_uid());

alter table api.pushes enable row level security;
create policy pushes_crud on api.pushes for all to app_user
  using (user_id = api.auth_uid())
  with check (user_id = api.auth_uid());

alter table api.subscriptions enable row level security;
create policy subs_crud on api.subscriptions for all to app_user
  using (user_id = api.auth_uid())
  with check (user_id = api.auth_uid());

alter table api.channels enable row level security;
create policy channels_read on api.channels for select to anon, app_user
  using (true);
create policy channels_insert on api.channels for insert to app_user
  with check (owner_id = api.auth_uid());
create policy channels_update on api.channels for update to app_user
  using (owner_id = api.auth_uid())
  with check (owner_id = api.auth_uid());

-- ----------------------------------------------------------------------------
-- Grants (tombstone deletes: no DELETE on pushes/devices; clients PATCH active=false)
-- ----------------------------------------------------------------------------
grant select, insert, update on api.devices       to app_user;
grant select, insert, update on api.pushes        to app_user;
grant select, insert, update on api.channels      to app_user;
grant select, insert, update, delete on api.subscriptions to app_user;
grant select on api.channels                      to anon;

commit;
