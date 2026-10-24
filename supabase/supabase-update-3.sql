-- Game Night Gauntlet: optional email accounts (Stage 1). Run once in the Supabase SQL editor.
alter table public.gauntlets add column if not exists owner_id uuid;
create index if not exists gauntlets_owner_idx on public.gauntlets(owner_id);

-- Link a gauntlet to the signed-in account (needs the admin code).
create or replace function public.claim_gauntlet(p_code text, p_secret text)
returns text language plpgsql security definer set search_path=public as $$
declare g public.gauntlets;
begin
  if auth.uid() is null then return 'auth'; end if;
  select * into g from public.gauntlets where code=p_code;
  if not found then return 'missing'; end if;
  if g.host_hash <> encode(sha256(convert_to(p_secret,'utf8')),'hex') then return 'denied'; end if;
  if g.owner_id is not null and g.owner_id <> auth.uid() then return 'denied'; end if;
  update public.gauntlets set owner_id=auth.uid() where code=p_code;
  return 'ok';
end $$;

-- List the signed-in account's gauntlets.
create or replace function public.my_gauntlets()
returns table(code text, meta jsonb, updated_at timestamptz)
language sql security definer set search_path=public as $$
  select code, meta, updated_at from public.gauntlets
  where owner_id=auth.uid() order by updated_at desc limit 50;
$$;

-- Take a gauntlet back on a new phone: rotates the admin code so the old device stops being able to write.
create or replace function public.recover_gauntlet(p_code text, p_new_secret text)
returns table(code text, data jsonb, meta jsonb)
language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or length(p_new_secret)<16 then return; end if;
  return query
  update public.gauntlets g set host_hash=encode(sha256(convert_to(p_new_secret,'utf8')),'hex')
  where g.code=p_code and g.owner_id=auth.uid()
  returning g.code, g.data, g.meta;
end $$;

revoke all on function public.claim_gauntlet(text,text), public.my_gauntlets(), public.recover_gauntlet(text,text) from public, anon;
grant execute on function public.claim_gauntlet(text,text), public.my_gauntlets(), public.recover_gauntlet(text,text) to authenticated;
