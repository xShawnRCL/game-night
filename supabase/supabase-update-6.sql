-- Game Night Gauntlet: update 6 (viewers can change their own game piece).
-- Paste into Supabase > SQL Editor > Run. Safe to run more than once. Run AFTER update 5.

alter table public.gauntlets add column if not exists looks jsonb not null default '{}'::jsonb;

-- A viewer changes how one player's piece looks. Only a few small whole numbers are accepted.
create or replace function public.set_player_look(p_code text, p_pid text, p_look jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare
  c int; h int; i int; p int; s int; clean jsonb; n int;
begin
  if p_pid is null or p_pid !~ '^p[0-9]{1,4}$' then raise exception 'bad player'; end if;
  if p_look is null or jsonb_typeof(p_look) <> 'object' or pg_column_size(p_look) > 400 then raise exception 'bad look'; end if;
  c := case when (p_look->>'c') ~ '^[0-9]{1,2}$' then (p_look->>'c')::int else 0 end;
  h := case when (p_look->>'h') ~ '^[0-9]{1,2}$' then (p_look->>'h')::int else 0 end;
  i := case when (p_look->>'i') ~ '^[0-9]{1,2}$' then (p_look->>'i')::int else 0 end;
  p := case when (p_look->>'p') ~ '^[0-9]{1,2}$' then (p_look->>'p')::int else 0 end;
  s := case when (p_look->>'s') ~ '^[0-9]{1,2}$' then (p_look->>'s')::int else 0 end;
  clean := jsonb_build_object('c', c, 'h', h, 'i', i, 'p', p, 's', s);
  update public.gauntlets
     set looks = coalesce(looks, '{}'::jsonb) || jsonb_build_object(p_pid, jsonb_build_object('look', clean, 't', (extract(epoch from clock_timestamp()) * 1000)::bigint))
   where code = upper(p_code) and pg_column_size(coalesce(looks, '{}'::jsonb)) < 20000;
  if found then return 'ok'; end if;
  return 'none';
end $$;

create or replace function public.get_looks(p_code text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce((select g.looks from public.gauntlets g where g.code = upper(p_code)), '{}'::jsonb);
$$;

revoke all on function public.set_player_look(text,text,jsonb), public.get_looks(text) from public;
grant execute on function public.set_player_look(text,text,jsonb), public.get_looks(text) to anon, authenticated;
