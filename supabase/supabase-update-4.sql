-- Game Night Gauntlet: update 4 (account deletion, spam limits, size guard).
-- Paste into Supabase > SQL Editor > Run. Safe to run more than once. Run AFTER update 3.

-- 1. Log of new-gauntlet creations, used to limit how fast one visitor can create them.
--    Only a one-way fingerprint of the visitor's address is kept, and rows are removed after 2 days.
create table if not exists public.create_log (
  who text not null,
  at  timestamptz not null default now()
);
create index if not exists create_log_who_at on public.create_log(who, at);
alter table public.create_log enable row level security;
revoke all on table public.create_log from anon, authenticated;

create or replace function public.guard_new_gauntlet() returns void
language plpgsql security definer set search_path = public as $$
declare
  hdr json := coalesce(nullif(current_setting('request.headers', true), '')::json, '{}'::json);
  ip  text := coalesce(hdr->>'cf-connecting-ip', split_part(coalesce(hdr->>'x-forwarded-for',''), ',', 1), 'unknown');
  w   text := encode(sha256(convert_to(ip,'utf8')),'hex');
begin
  -- Safety valve: stop accepting NEW gauntlets well before the free 500 MB database fills.
  if pg_total_relation_size('public.gauntlets') > 350 * 1024 * 1024 then
    raise exception 'capacity';
  end if;
  delete from public.create_log where at < now() - interval '2 days';
  -- A family makes a few gauntlets, not dozens: 30 new ones per visitor per hour is generous.
  if (select count(*) from public.create_log where who = w and at > now() - interval '1 hour') >= 30 then
    raise exception 'rate';
  end if;
  insert into public.create_log(who) values (w);
end $$;
revoke all on function public.guard_new_gauntlet() from public, anon, authenticated;

-- 2. save_gauntlet: updates first; only a genuinely new code passes through the guard.
create or replace function public.save_gauntlet(
  p_code text, p_secret text, p_data jsonb,
  p_fmt int default 1, p_meta jsonb default '{}'::jsonb, p_app text default null
) returns text language plpgsql security definer set search_path = public as $$
declare h text := encode(sha256(convert_to(p_secret,'utf8')),'hex');
begin
  if length(coalesce(p_secret,'')) < 16 then raise exception 'secret too short'; end if;
  if pg_column_size(p_data) > 2000000 then raise exception 'data too large'; end if;
  update public.gauntlets
     set data = p_data, fmt = p_fmt, meta = p_meta, app_version = p_app, updated_at = now()
   where code = upper(p_code) and host_hash = h;
  if found then return 'ok'; end if;
  if exists (select 1 from public.gauntlets where code = upper(p_code)) then return 'taken'; end if;
  perform public.guard_new_gauntlet();
  begin
    insert into public.gauntlets (code, host_hash, fmt, data, meta, app_version)
    values (upper(p_code), h, p_fmt, p_data, p_meta, p_app);
    return 'ok';
  exception when unique_violation then
    return 'taken';
  end;
end $$;

create or replace function public.create_gauntlet(
  p_code text, p_secret text, p_data jsonb,
  p_fmt int default 1, p_meta jsonb default '{}'::jsonb, p_app text default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  if length(coalesce(p_secret,'')) < 16 then raise exception 'secret too short'; end if;
  if pg_column_size(p_data) > 2000000 then raise exception 'data too large'; end if;
  perform public.guard_new_gauntlet();
  insert into public.gauntlets (code, host_hash, fmt, data, meta, app_version)
  values (upper(p_code), encode(sha256(convert_to(p_secret,'utf8')),'hex'), p_fmt, p_data, p_meta, p_app);
end $$;

-- 3. Delete my account: removes every gauntlet linked to the signed-in account, then the account itself.
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  delete from public.gauntlets where owner_id = auth.uid();
  delete from auth.users where id = auth.uid();
end $$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
