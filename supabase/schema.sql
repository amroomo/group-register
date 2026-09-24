-- Student group registration
--
-- 1. In the Supabase SQL editor, replace CHANGE_ME with your admin password.
-- 2. Run this script.
-- 3. Do not save that password into the copy of this file that you push to GitHub.
--
-- To change the password later, run only this line in the SQL editor:
--   update private.secrets set admin_password = 'your-new-password' where id = 1;

create schema if not exists private;

revoke all on schema private from public;
revoke all on schema private from anon, authenticated;

create table if not exists private.secrets (
  id int primary key check (id = 1),
  admin_password text not null
);

insert into private.secrets (id, admin_password)
values (1, 'CHANGE_ME')
on conflict (id) do nothing;

alter table private.secrets enable row level security;

revoke all on table private.secrets from public, anon, authenticated;

create table if not exists public.registrations (
  id uuid primary key default gen_random_uuid(),
  full_name text not null check (char_length(btrim(full_name)) between 5 and 120),
  phone text not null check (char_length(phone) between 8 and 20),
  phone_key text generated always as (regexp_replace(phone, '[^0-9]', '', 'g')) stored,
  group_day text not null check (
    group_day in (
      'sunday',
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday'
    )
  ),
  created_at timestamptz not null default now(),
  constraint registrations_phone_key_unique unique (phone_key),
  constraint registrations_phone_key_len check (char_length(phone_key) between 8 and 15)
);

alter table public.registrations enable row level security;

revoke all on table public.registrations from public, anon, authenticated;

create or replace function public.seat_counts()
returns table (group_day text, taken integer)
language sql
stable
security definer
set search_path = public
as $$
  select days.group_day, coalesce(counts.taken, 0)::integer
  from (
    values
      ('sunday'),
      ('monday'),
      ('tuesday'),
      ('wednesday'),
      ('thursday'),
      ('friday'),
      ('saturday')
  ) as days(group_day)
  left join (
    select registrations.group_day, count(*)::integer as taken
    from public.registrations
    group by registrations.group_day
  ) as counts on counts.group_day = days.group_day;
$$;

create or replace function public.register_student(
  p_full_name text,
  p_phone text,
  p_group_day text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_name text;
  clean_phone text;
  phone_digits text;
  taken integer;
  capacity constant integer := 30;
  allowed text[] := array[
    'sunday',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday'
  ];
begin
  clean_name := btrim(coalesce(p_full_name, ''));
  clean_phone := btrim(coalesce(p_phone, ''));
  phone_digits := regexp_replace(clean_phone, '[^0-9]', '', 'g');

  if char_length(clean_name) < 5 or char_length(clean_name) > 120 then
    return jsonb_build_object('ok', false, 'error', 'name');
  end if;

  if char_length(phone_digits) < 8 or char_length(phone_digits) > 15 or char_length(clean_phone) > 20 then
    return jsonb_build_object('ok', false, 'error', 'phone');
  end if;

  if p_group_day is null or not (p_group_day = any (allowed)) then
    return jsonb_build_object('ok', false, 'error', 'group');
  end if;

  perform pg_advisory_xact_lock(hashtext('group:' || p_group_day));

  if exists (
    select 1
    from public.registrations
    where phone_key = phone_digits
  ) then
    return jsonb_build_object('ok', false, 'error', 'duplicate');
  end if;

  select count(*)::integer
  into taken
  from public.registrations
  where registrations.group_day = p_group_day;

  if taken >= capacity then
    return jsonb_build_object('ok', false, 'error', 'full');
  end if;

  insert into public.registrations (full_name, phone, group_day)
  values (clean_name, phone_digits, p_group_day);

  return jsonb_build_object('ok', true);
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'error', 'duplicate');
end;
$$;

create or replace function public.list_registrations(p_password text)
returns jsonb
language plpgsql
security definer
set search_path = public, private
as $$
declare
  expected text;
  rows jsonb;
begin
  select admin_password
  into expected
  from private.secrets
  where id = 1;

  if expected is null or expected = 'CHANGE_ME' then
    return jsonb_build_object('ok', false, 'error', 'setup');
  end if;

  if p_password is distinct from expected then
    return jsonb_build_object('ok', false, 'error', 'password');
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'full_name', registrations.full_name,
        'phone', registrations.phone,
        'group_day', registrations.group_day,
        'created_at', registrations.created_at
      )
      order by registrations.created_at desc
    ),
    '[]'::jsonb
  )
  into rows
  from public.registrations;

  return jsonb_build_object('ok', true, 'rows', rows);
end;
$$;

revoke all on function public.seat_counts() from public;
revoke all on function public.register_student(text, text, text) from public;
revoke all on function public.list_registrations(text) from public;

grant execute on function public.seat_counts() to anon, authenticated;
grant execute on function public.register_student(text, text, text) to anon, authenticated;
grant execute on function public.list_registrations(text) to anon, authenticated;
