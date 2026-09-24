-- Run this once in the Supabase SQL editor.
-- It lets each student register for exactly two different groups.
-- Do not change the admin password here.

alter table public.registrations
  add column if not exists group_day_2 text;

alter table public.registrations
  drop constraint if exists registrations_two_groups_distinct;

alter table public.registrations
  add constraint registrations_two_groups_distinct
  check (
    group_day_2 is null
    or (
      group_day_2 in (
        'sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'
      )
      and group_day_2 <> group_day
    )
  );
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
  clean_phone text;
  phone_digits text;
  taken_first integer;
  taken_second integer;
  capacity constant integer := 30;
  first_day text;
  second_day text;
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

  if p_group_day is null or p_group_day_2 is null
     or not (p_group_day = any (allowed))
     or not (p_group_day_2 = any (allowed)) then
    return jsonb_build_object('ok', false, 'error', 'group');
  end if;

  if p_group_day = p_group_day_2 then
    return jsonb_build_object('ok', false, 'error', 'same');
  end if;

  if p_group_day < p_group_day_2 then
    first_day := p_group_day;
    second_day := p_group_day_2;
  else
    first_day := p_group_day_2;
    second_day := p_group_day;
  end if;

  perform pg_advisory_xact_lock(hashtext('group:' || first_day));
  perform pg_advisory_xact_lock(hashtext('group:' || second_day));

  if exists (
    select 1
    from public.registrations
    where phone_key = phone_digits
  ) then
    return jsonb_build_object('ok', false, 'error', 'duplicate');
  end if;

  select count(*)::integer
  into taken_first
  from public.registrations
  where group_day = p_group_day or group_day_2 = p_group_day;

  select count(*)::integer
  into taken_second
  from public.registrations
  where group_day = p_group_day_2 or group_day_2 = p_group_day_2;

  if taken_first >= capacity or taken_second >= capacity then
    return jsonb_build_object('ok', false, 'error', 'full');
  end if;

  insert into public.registrations (full_name, phone, group_day, group_day_2)
  values (clean_name, phone_digits, p_group_day, p_group_day_2);

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

revoke all on function public.seat_counts() from public;
revoke all on function public.register_student(text, text, text, text) from public;
revoke all on function public.list_registrations(text) from public;

grant execute on function public.seat_counts() to anon, authenticated;
grant execute on function public.register_student(text, text, text, text) to anon, authenticated;
grant execute on function public.list_registrations(text) to anon, authenticated;

