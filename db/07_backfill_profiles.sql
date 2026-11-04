-- Create profiles rows for users who signed up before the trigger existed.
--
-- 01 added handle_new_user_profile, which fills profiles on signup. Anyone who
-- registered before that has no row, so they are invisible to the portal
-- directory and to SAM even when they are assigned and have sessions.
--
-- Run once in: Supabase dashboard -> SQL Editor. Safe to re-run.

insert into public.profiles (user_id, full_name, email, role)
select
  u.id,
  nullif(u.raw_user_meta_data ->> 'full_name', ''),
  u.email,
  case
    when u.raw_user_meta_data ->> 'role' in ('doctor', 'patient')
      then u.raw_user_meta_data ->> 'role'
    else 'patient'
  end
from auth.users u
left join public.profiles p on p.user_id = u.id
where p.user_id is null
on conflict (user_id) do nothing;

-- Anyone still missing a display name shows as their email in the UI, which is
-- better than a blank row. Only touches rows that have no name at all.
update public.profiles
set full_name = email
where full_name is null or trim(full_name) = '';

select
  (select count(*) from auth.users)        as auth_users,
  (select count(*) from public.profiles)   as profiles,
  (select count(*) from auth.users u
     left join public.profiles p on p.user_id = u.id
    where p.user_id is null)               as still_missing;
