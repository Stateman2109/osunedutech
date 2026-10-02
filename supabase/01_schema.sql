-- =====================================================================
-- OSUN EDUTECH – student location data + government access
-- Run once in Supabase  ->  SQL Editor.  Safe to re-run.
-- =====================================================================

-- 1. New columns on profiles --------------------------------------------------
alter table public.profiles add column if not exists email        text;
alter table public.profiles add column if not exists lga          text;
alter table public.profiles add column if not exists school_name  text;
alter table public.profiles add column if not exists class_level  text;
alter table public.profiles add column if not exists school_type  text default 'public';
alter table public.profiles add column if not exists created_at   timestamptz default now();

alter table public.profiles drop constraint if exists profiles_school_type_chk;
alter table public.profiles add constraint profiles_school_type_chk
  check (school_type in ('public','private'));

-- 2. New columns on results ---------------------------------------------------
alter table public.results add column if not exists subject   text;
alter table public.results add column if not exists exam_year int;

create index if not exists idx_profiles_lga_school on public.profiles (lga, school_name);
create index if not exists idx_results_user        on public.results (user_id);

-- 3. Create the profile automatically on sign-up -------------------------------
--    Runs inside the database, so the LGA/school/class are saved even when email
--    confirmation is ON (no session yet). The role is ALWAYS 'student' here:
--    nobody can make themselves admin/government from the browser.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, email, role, lga, school_name, class_level, school_type)
  values (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.email,
    'student',
    new.raw_user_meta_data->>'lga',
    new.raw_user_meta_data->>'school_name',
    new.raw_user_meta_data->>'class_level',
    coalesce(nullif(new.raw_user_meta_data->>'school_type',''), 'public')
  )
  on conflict (id) do update set
    full_name    = excluded.full_name,
    email        = excluded.email,
    lga          = excluded.lga,
    school_name  = excluded.school_name,
    class_level  = excluded.class_level,
    school_type  = excluded.school_type;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 4. Helper: is the caller government / admin? ---------------------------------
create or replace function public.is_government()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles
                 where id = auth.uid() and role in ('government','admin'));
$$;

-- 5. Row Level Security --------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.results  enable row level security;

drop policy if exists "profiles_select_own"  on public.profiles;
drop policy if exists "profiles_select_gov"  on public.profiles;
drop policy if exists "profiles_update_own"  on public.profiles;
create policy "profiles_select_own" on public.profiles for select using (id = auth.uid());
create policy "profiles_select_gov" on public.profiles for select using (public.is_government());
-- students may edit their own record but may NOT change their role
create policy "profiles_update_own" on public.profiles for update
  using (id = auth.uid())
  with check (id = auth.uid()
              and role = (select p.role from public.profiles p where p.id = auth.uid()));

drop policy if exists "results_select_own" on public.results;
drop policy if exists "results_select_gov" on public.results;
drop policy if exists "results_insert_own" on public.results;
create policy "results_select_own" on public.results for select using (user_id = auth.uid());
create policy "results_select_gov" on public.results for select using (public.is_government());
create policy "results_insert_own" on public.results for insert with check (user_id = auth.uid());

-- 6. School suggestions for the register page (no personal data exposed) --------
create or replace function public.get_schools_by_lga(p_lga text)
returns table (school_name text) language sql stable security definer set search_path = public as $$
  select distinct school_name from public.profiles
  where lga = p_lga and school_name is not null and school_name <> ''
  order by school_name;
$$;
grant execute on function public.get_schools_by_lga(text) to anon, authenticated;

-- 7. Examination irregularities (the exam page can insert rows when it detects
--    tab-switching, multiple logins, etc. The government dashboard reads this.)
create table if not exists public.exam_incidents (
  id          bigint generated always as identity primary key,
  user_id     uuid references auth.users(id),
  result_id   bigint,
  kind        text not null,            -- e.g. 'tab_switch', 'copy_paste', 'duplicate_session'
  details     text,
  created_at  timestamptz default now()
);
alter table public.exam_incidents enable row level security;
drop policy if exists "incidents_insert_own" on public.exam_incidents;
drop policy if exists "incidents_select_gov" on public.exam_incidents;
create policy "incidents_insert_own" on public.exam_incidents for insert with check (user_id = auth.uid());
create policy "incidents_select_gov" on public.exam_incidents for select using (public.is_government());

-- 8. Make someone a government user (run manually, with the real email) ---------
-- update public.profiles set role = 'government' where email = 'ministry@example.com';
