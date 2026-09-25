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
  group_day text not null,
  group_day_2 text not null,
  constraint registrations_group_days_check check (
    group_day in (
      'sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'
    )
    and group_day_2 in (
      'sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'
    )
    and group_day <> group_day_2
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
    select chosen.group_day, count(*)::integer as taken
    from (
      select group_day from public.registrations
      union all
      select group_day_2 from public.registrations
    ) as chosen
    group by chosen.group_day
  ) as counts on counts.group_day = days.group_day;
$$;

create or replace function public.canonical_phone(p_phone text)
returns text
language plpgsql
immutable
as $$
declare
  digits text;
begin
  digits := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  if digits ~ '^00' then
    digits := substring(digits from 3);
  end if;
  if digits ~ '^966' then
    return digits;
  elsif digits ~ '^0' then
    return '966' || substring(digits from 2);
  else
    return '966' || digits;
  end if;
end;
$$;

drop function if exists public.register_student(text, text, text);

create or replace function public.register_student(
  p_full_name text,
  p_phone text,
  p_group_day text,
  p_group_day_2 text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_name text;
  phone_digits text;
  taken_first integer;
  taken_second integer;
  capacity constant integer := 30;
  existing_id uuid;
  old_day text;
  old_day_2 text;
  day text;
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
  phone_digits := public.canonical_phone(p_phone);

  if char_length(clean_name) < 5 or char_length(clean_name) > 120 then
    return jsonb_build_object('ok', false, 'error', 'name');
  end if;

  if phone_digits !~ '^966[0-9]{9,12}$' then
    return jsonb_build_object('ok', false, 'error', 'phone');
  end if;

  if p_group_day is null or p_group_day_2 is null
     or not (p_group_day = any (allowed))
     or not (p_group_day_2 = any (allowed)) then
    return jsonb_build_object('ok', false, 'error', 'group');
  end if;

  if p_group_day = p_group_day_2 then
    return jsonb_build_object('ok', false, 'error', 'same');
  end if;

  select id, group_day, group_day_2
  into existing_id, old_day, old_day_2
  from public.registrations
  where phone_key = phone_digits;

  for day in
    select distinct chosen.day
    from unnest(array[p_group_day, p_group_day_2, old_day, old_day_2]) as chosen(day)
    where chosen.day is not null
    order by chosen.day
  loop
    perform pg_advisory_xact_lock(hashtext('group:' || day));
  end loop;

  if existing_id is not null
     and (
       (old_day = p_group_day and old_day_2 = p_group_day_2)
       or (old_day = p_group_day_2 and old_day_2 = p_group_day)
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', 'duplicate',
      'group_day', old_day,
      'group_day_2', old_day_2
    );
  end if;

  select count(*)::integer
  into taken_first
  from public.registrations
  where (group_day = p_group_day or group_day_2 = p_group_day)
    and (existing_id is null or id <> existing_id);

  select count(*)::integer
  into taken_second
  from public.registrations
  where (group_day = p_group_day_2 or group_day_2 = p_group_day_2)
    and (existing_id is null or id <> existing_id);

  if taken_first >= capacity or taken_second >= capacity then
    return jsonb_build_object('ok', false, 'error', 'full');
  end if;

  if existing_id is not null then
    update public.registrations
    set full_name = clean_name,
        phone = phone_digits,
        group_day = p_group_day,
        group_day_2 = p_group_day_2
    where id = existing_id;

    return jsonb_build_object('ok', true, 'updated', true);
  end if;

  insert into public.registrations (full_name, phone, group_day, group_day_2)
  values (clean_name, phone_digits, p_group_day, p_group_day_2);

  return jsonb_build_object('ok', true, 'updated', false);
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
        'group_day_2', registrations.group_day_2,
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

create or replace function public.lookup_student(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  phone_digits text;
  found_name text;
  found_day text;
  found_day_2 text;
begin
  phone_digits := public.canonical_phone(p_phone);

  if phone_digits !~ '^966[0-9]{9,12}$' then
    return jsonb_build_object('ok', false, 'error', 'phone');
  end if;

  select full_name, group_day, group_day_2
  into found_name, found_day, found_day_2
  from public.registrations
  where phone_key = phone_digits;

  if found_name is null then
    return jsonb_build_object('ok', true, 'found', false);
  end if;

  return jsonb_build_object(
    'ok', true,
    'found', true,
    'full_name', found_name,
    'group_day', found_day,
    'group_day_2', found_day_2
  );
end;
$$;

revoke all on function public.seat_counts() from public;
revoke all on function public.lookup_student(text) from public;
revoke all on function public.canonical_phone(text) from public;
revoke all on function public.register_student(text, text, text, text) from public;
revoke all on function public.list_registrations(text) from public;

grant execute on function public.seat_counts() to anon, authenticated;
grant execute on function public.lookup_student(text) to anon, authenticated;
grant execute on function public.register_student(text, text, text, text) to anon, authenticated;
grant execute on function public.list_registrations(text) to anon, authenticated;
