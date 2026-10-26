-- Game Night Gauntlet: update 5 (saved players and meeple designs follow your account).
-- Paste into Supabase > SQL Editor > Run. Safe to run more than once. Run AFTER update 4.

create table if not exists public.user_roster (
  owner_id uuid primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.user_roster enable row level security;
revoke all on table public.user_roster from anon, authenticated;

create or replace function public.get_my_roster() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  return coalesce((select data from public.user_roster where owner_id = auth.uid()), '{}'::jsonb);
end $$;

create or replace function public.save_my_roster(p_data jsonb) returns text
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if pg_column_size(p_data) > 200000 then raise exception 'data too large'; end if;
  insert into public.user_roster(owner_id, data) values (auth.uid(), p_data)
  on conflict (owner_id) do update set data = excluded.data, updated_at = now();
  return 'ok';
end $$;

revoke all on function public.get_my_roster(), public.save_my_roster(jsonb) from public, anon;
grant execute on function public.get_my_roster(), public.save_my_roster(jsonb) to authenticated;

-- Account deletion now removes the saved players too.
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  delete from public.gauntlets where owner_id = auth.uid();
  delete from public.user_roster where owner_id = auth.uid();
  delete from auth.users where id = auth.uid();
end $$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- Remove one of your own online gauntlets from the account list (and delete its online copy).
create or replace function public.delete_my_gauntlet(p_code text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  delete from public.gauntlets where code = upper(p_code) and owner_id = auth.uid();
end $$;
revoke all on function public.delete_my_gauntlet(text) from public, anon;
grant execute on function public.delete_my_gauntlet(text) to authenticated;
