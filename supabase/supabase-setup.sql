-- Game Night Gauntlet: live sharing setup. Paste all of this into Supabase > SQL Editor > Run.
-- Safe to run more than once.

create table if not exists public.gauntlets (
  code        text primary key check (code ~ '^[A-Z0-9]{6}$'),
  host_hash   text not null,                 -- fingerprint of the host's secret, never the secret itself
  fmt         int  not null default 1,       -- data format version
  data        jsonb not null,                -- the whole gauntlet
  meta        jsonb not null default '{}'::jsonb,  -- small summary (players, rounds, phase, name) for later use
  app_version text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Lock the table: nobody can touch it directly. Everything goes through the functions below.
alter table public.gauntlets enable row level security;
revoke all on table public.gauntlets from anon, authenticated;

create or replace function public.create_gauntlet(
  p_code text, p_secret text, p_data jsonb,
  p_fmt int default 1, p_meta jsonb default '{}'::jsonb, p_app text default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  if length(coalesce(p_secret,'')) < 16 then raise exception 'secret too short'; end if;
  if pg_column_size(p_data) > 2000000 then raise exception 'data too large'; end if;
  insert into public.gauntlets (code, host_hash, fmt, data, meta, app_version)
  values (upper(p_code), encode(sha256(convert_to(p_secret,'utf8')),'hex'), p_fmt, p_data, p_meta, p_app);
end $$;

create or replace function public.update_gauntlet(
  p_code text, p_secret text, p_data jsonb,
  p_fmt int default 1, p_meta jsonb default '{}'::jsonb, p_app text default null
) returns boolean language plpgsql security definer set search_path = public as $$
begin
  if pg_column_size(p_data) > 2000000 then raise exception 'data too large'; end if;
  update public.gauntlets
     set data = p_data, fmt = p_fmt, meta = p_meta, app_version = p_app, updated_at = now()
   where code = upper(p_code)
     and host_hash = encode(sha256(convert_to(p_secret,'utf8')),'hex');
  return found;
end $$;

create or replace function public.get_gauntlet(p_code text)
returns table (data jsonb, fmt int, updated_at timestamptz)
language sql stable security definer set search_path = public as $$
  select g.data, g.fmt, g.updated_at from public.gauntlets g where g.code = upper(p_code);
$$;

create or replace function public.delete_gauntlet(p_code text, p_secret text)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  delete from public.gauntlets
   where code = upper(p_code)
     and host_hash = encode(sha256(convert_to(p_secret,'utf8')),'hex');
  return found;
end $$;

-- Only these four functions are open to the app.
revoke all on function public.create_gauntlet(text,text,jsonb,int,jsonb,text) from public;
revoke all on function public.update_gauntlet(text,text,jsonb,int,jsonb,text) from public;
revoke all on function public.get_gauntlet(text) from public;
revoke all on function public.delete_gauntlet(text,text) from public;
grant execute on function public.create_gauntlet(text,text,jsonb,int,jsonb,text) to anon;
grant execute on function public.update_gauntlet(text,text,jsonb,int,jsonb,text) to anon;
grant execute on function public.get_gauntlet(text) to anon;
grant execute on function public.delete_gauntlet(text,text) to anon;
