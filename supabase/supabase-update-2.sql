-- Game Night Gauntlet: update 2. Paste into Supabase > SQL Editor > Run. Safe to run more than once.
-- Run this AFTER supabase-setup.sql.

-- Create the gauntlet if it is new, or update it if the secret matches. Returns 'ok' or 'taken'.
create or replace function public.save_gauntlet(
  p_code text, p_secret text, p_data jsonb,
  p_fmt int default 1, p_meta jsonb default '{}'::jsonb, p_app text default null
) returns text language plpgsql security definer set search_path = public as $$
declare h text := encode(sha256(convert_to(p_secret,'utf8')),'hex');
begin
  if length(coalesce(p_secret,'')) < 16 then raise exception 'secret too short'; end if;
  if pg_column_size(p_data) > 2000000 then raise exception 'data too large'; end if;
  begin
    insert into public.gauntlets (code, host_hash, fmt, data, meta, app_version)
    values (upper(p_code), h, p_fmt, p_data, p_meta, p_app);
    return 'ok';
  exception when unique_violation then
    update public.gauntlets
       set data = p_data, fmt = p_fmt, meta = p_meta, app_version = p_app, updated_at = now()
     where code = upper(p_code) and host_hash = h;
    if found then return 'ok'; end if;
    return 'taken';
  end;
end $$;

-- Let a host open their own gauntlet on another phone using only the admin code.
create or replace function public.get_by_admin(p_secret text)
returns table (code text, data jsonb, fmt int, updated_at timestamptz)
language sql stable security definer set search_path = public as $$
  select g.code, g.data, g.fmt, g.updated_at from public.gauntlets g
   where length(coalesce(p_secret,'')) >= 16
     and g.host_hash = encode(sha256(convert_to(p_secret,'utf8')),'hex');
$$;

revoke all on function public.save_gauntlet(text,text,jsonb,int,jsonb,text) from public;
revoke all on function public.get_by_admin(text) from public;
grant execute on function public.save_gauntlet(text,text,jsonb,int,jsonb,text) to anon;
grant execute on function public.get_by_admin(text) to anon;
