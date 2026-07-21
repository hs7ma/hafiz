-- Hafiz: full Supabase backend alignment (schema + RLS + private helpers)
-- Aligns with Express/Postgres production tables; tightens RLS; adds Auth linking
-- and opaque sessions for platform / teacher / student.

create extension if not exists "pgcrypto";

create schema if not exists private;

do $$ begin
  create type public.user_role as enum ('mosque_admin', 'teacher', 'student');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.attendance_status as enum ('unmarked', 'present', 'absent', 'late');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.session_status as enum ('active', 'completed', 'cancelled');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.memorization_level as enum (
    'not_memorized', 'poor', 'average', 'good', 'very_good', 'excellent'
  );
exception when duplicate_object then null;
end $$;

create table if not exists public.mosques (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

alter table public.mosques
  add column if not exists whatsapp_phone text;

create table if not exists public.mosque_admins (
  id uuid primary key default gen_random_uuid(),
  mosque_id uuid not null references public.mosques(id) on delete cascade,
  full_name text not null,
  email text not null unique,
  password_hash text,
  created_at timestamptz not null default now()
);

-- Link to Supabase Auth (nullable during dual-login migration)
alter table public.mosque_admins
  add column if not exists auth_user_id uuid unique references auth.users(id) on delete set null;

create table if not exists public.teachers (
  id uuid primary key default gen_random_uuid(),
  mosque_id uuid not null references public.mosques(id) on delete cascade,
  full_name text not null,
  english_name text not null,
  english_prefix char(2) not null,
  login_code text not null,
  created_at timestamptz not null default now(),
  unique (mosque_id, login_code),
  unique (mosque_id, full_name)
);

create table if not exists public.students (
  id uuid primary key default gen_random_uuid(),
  mosque_id uuid not null references public.mosques(id) on delete cascade,
  teacher_id uuid not null references public.teachers(id) on delete cascade,
  full_name text not null,
  grade_level text not null,
  age int not null check (age between 4 and 25),
  parent_phone text not null,
  login_username text not null,
  login_code text not null,
  created_at timestamptz not null default now(),
  unique (mosque_id, login_username)
);

create table if not exists public.sessions (
  id uuid primary key default gen_random_uuid(),
  mosque_id uuid not null references public.mosques(id) on delete cascade,
  teacher_id uuid not null references public.teachers(id) on delete cascade,
  session_date date not null,
  status public.session_status not null default 'active',
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  unique (teacher_id, session_date)
);

create table if not exists public.attendance (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  status public.attendance_status not null default 'unmarked',
  memorization_level public.memorization_level,
  behavior_score int check (behavior_score is null or (behavior_score between 0 and 10)),
  marked_at timestamptz,
  unique (session_id, student_id)
);

create table if not exists public.student_homework (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null unique references public.students(id) on delete cascade,
  surah_number int not null check (surah_number between 1 and 114),
  from_ayah int not null check (from_ayah >= 1),
  to_ayah int not null check (to_ayah >= from_ayah),
  note text default '',
  assigned_at timestamptz not null default now()
);

create table if not exists public.progress (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null unique references public.students(id) on delete cascade,
  surah_number int not null check (surah_number between 1 and 114),
  ayah_number int not null check (ayah_number >= 1),
  updated_at timestamptz not null default now()
);

create table if not exists public.mosque_registration_requests (
  id uuid primary key default gen_random_uuid(),
  mosque_name text not null,
  email text not null,
  whatsapp_phone text not null,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  mosque_id uuid references public.mosques(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

-- Opaque sessions for platform admin and code-based actors (teacher/student)
create table if not exists public.platform_sessions (
  token text primary key,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create table if not exists public.actor_sessions (
  token text primary key,
  role text not null check (role in ('mosque_admin', 'teacher', 'student')),
  actor_id uuid not null,
  mosque_id uuid not null references public.mosques(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create index if not exists idx_teachers_mosque on public.teachers (mosque_id);
create index if not exists idx_teachers_login on public.teachers (full_name, login_code);
create index if not exists idx_students_teacher on public.students (teacher_id);
create index if not exists idx_students_login on public.students (login_username, login_code);
create index if not exists idx_sessions_teacher_date on public.sessions (teacher_id, session_date);
create index if not exists idx_attendance_session on public.attendance (session_id);
create index if not exists idx_homework_student on public.student_homework (student_id);
create index if not exists mosque_registration_requests_status_idx
  on public.mosque_registration_requests (status);
create index if not exists mosque_registration_requests_email_idx
  on public.mosque_registration_requests (email);
create index if not exists idx_mosque_admins_auth_user on public.mosque_admins (auth_user_id);
create index if not exists idx_actor_sessions_mosque on public.actor_sessions (mosque_id);
create index if not exists idx_actor_sessions_expires on public.actor_sessions (expires_at);

-- ---------------------------------------------------------------------------
-- Private helpers (security definer — not in exposed API schema)
-- ---------------------------------------------------------------------------

create or replace function private.current_admin_mosque_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select mosque_id
  from public.mosque_admins
  where auth_user_id = (select auth.uid())
     or (auth_user_id is null and id = (select auth.uid()))
  limit 1
$$;

create or replace function private.is_mosque_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.mosque_admins
    where auth_user_id = (select auth.uid())
       or (auth_user_id is null and id = (select auth.uid()))
  )
$$;

create or replace function private.is_platform_session(p_token text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.platform_sessions
    where token = p_token and expires_at > now()
  )
$$;

revoke all on function private.current_admin_mosque_id() from public;
revoke all on function private.is_mosque_admin() from public;
revoke all on function private.is_platform_session(text) from public;
grant execute on function private.current_admin_mosque_id() to authenticated;
grant execute on function private.is_mosque_admin() to authenticated;

-- Thin public wrappers for RLS (keep names used by policies)
create or replace function public.current_admin_mosque_id()
returns uuid
language sql
stable
security invoker
set search_path = public, private
as $$
  select private.current_admin_mosque_id()
$$;

create or replace function public.is_mosque_admin()
returns boolean
language sql
stable
security invoker
set search_path = public, private
as $$
  select private.is_mosque_admin()
$$;

grant execute on function public.current_admin_mosque_id() to authenticated;
grant execute on function public.is_mosque_admin() to authenticated;

-- Teacher / student login RPCs (read-only credential check for Edge or client)
create or replace function public.login_teacher(p_full_name text, p_login_code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.teachers%rowtype;
  v_mosque_name text;
begin
  select * into v_row
  from public.teachers
  where full_name = trim(p_full_name)
    and upper(login_code) = upper(trim(p_login_code))
  limit 1;

  if not found then
    return null;
  end if;

  select name into v_mosque_name from public.mosques where id = v_row.mosque_id;

  return json_build_object(
    'id', v_row.id,
    'full_name', v_row.full_name,
    'english_name', v_row.english_name,
    'english_prefix', v_row.english_prefix,
    'login_code', v_row.login_code,
    'mosque_id', v_row.mosque_id,
    'mosque_name', v_mosque_name,
    'created_at', v_row.created_at
  );
end;
$$;

create or replace function public.login_student(p_username text, p_login_code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.students%rowtype;
  v_mosque_name text;
begin
  select * into v_row
  from public.students
  where login_username = trim(p_username)
    and upper(login_code) = upper(trim(p_login_code))
  limit 1;

  if not found then
    return null;
  end if;

  select name into v_mosque_name from public.mosques where id = v_row.mosque_id;

  return json_build_object(
    'id', v_row.id,
    'full_name', v_row.full_name,
    'grade_level', v_row.grade_level,
    'age', v_row.age,
    'parent_phone', v_row.parent_phone,
    'mosque_id', v_row.mosque_id,
    'teacher_id', v_row.teacher_id,
    'login_username', v_row.login_username,
    'login_code', v_row.login_code,
    'mosque_name', v_mosque_name,
    'created_at', v_row.created_at
  );
end;
$$;

-- Public registration submit (no password generation; no select of secrets)
create or replace function public.submit_registration_request(
  p_mosque_name text,
  p_email text,
  p_whatsapp_phone text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := trim(p_mosque_name);
  v_email text := lower(trim(p_email));
  v_phone text := regexp_replace(coalesce(p_whatsapp_phone, ''), '\D', '', 'g');
  v_row public.mosque_registration_requests%rowtype;
begin
  if v_name = '' then
    raise exception 'أدخل اسم الجامع';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'البريد غير صالح';
  end if;
  if length(v_phone) < 10 or length(v_phone) > 15 then
    raise exception 'رقم واتساب غير صالح';
  end if;
  if v_phone like '00%' then
    v_phone := substr(v_phone, 3);
  end if;
  if v_phone like '0%' and length(v_phone) >= 9 then
    v_phone := '966' || substr(v_phone, 2);
  end if;

  if exists (select 1 from public.mosques where name = v_name) then
    raise exception 'يوجد مسجد بهذا الاسم مسبقًا';
  end if;
  if exists (select 1 from public.mosque_admins where email = v_email) then
    raise exception 'البريد مستخدم مسبقًا';
  end if;
  if exists (
    select 1 from public.mosque_registration_requests
    where status = 'pending' and (email = v_email or mosque_name = v_name)
  ) then
    raise exception 'يوجد طلب قيد المراجعة لنفس البريد أو اسم الجامع';
  end if;

  insert into public.mosque_registration_requests
    (mosque_name, email, whatsapp_phone, status)
  values (v_name, v_email, v_phone, 'pending')
  returning * into v_row;

  return json_build_object(
    'request', json_build_object(
      'id', v_row.id,
      'mosque_name', v_row.mosque_name,
      'email', v_row.email,
      'whatsapp_phone', v_row.whatsapp_phone,
      'status', v_row.status,
      'mosque_id', v_row.mosque_id,
      'reviewed_at', v_row.reviewed_at,
      'created_at', v_row.created_at
    ),
    'message', 'تم إرسال الطلب. انتظر موافقة إدارة حافظ.'
  );
end;
$$;

grant execute on function public.login_teacher(text, text) to anon, authenticated;
grant execute on function public.login_student(text, text) to anon, authenticated;
grant execute on function public.submit_registration_request(text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- RLS: enable on all public tables; drop overly-permissive anon write policies
-- ---------------------------------------------------------------------------

alter table public.mosques enable row level security;
alter table public.mosque_admins enable row level security;
alter table public.teachers enable row level security;
alter table public.students enable row level security;
alter table public.sessions enable row level security;
alter table public.attendance enable row level security;
alter table public.student_homework enable row level security;
alter table public.progress enable row level security;
alter table public.mosque_registration_requests enable row level security;
alter table public.platform_sessions enable row level security;
alter table public.actor_sessions enable row level security;

-- Drop legacy open anon policies if present
do $$
declare
  pol record;
begin
  for pol in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and (
        policyname ilike '%anon%'
        or policyname in (
          'mosques_select_anon_bridge',
          'teachers_anon_select', 'teachers_anon_insert', 'teachers_anon_update', 'teachers_anon_delete',
          'students_anon_select', 'students_anon_insert', 'students_anon_update', 'students_anon_delete',
          'sessions_anon_select', 'sessions_anon_insert', 'sessions_anon_update', 'sessions_anon_delete',
          'attendance_anon_select', 'attendance_anon_insert', 'attendance_anon_update', 'attendance_anon_delete',
          'homework_anon_select', 'homework_anon_insert', 'homework_anon_update', 'homework_anon_delete',
          'progress_anon_select', 'progress_anon_insert', 'progress_anon_update', 'progress_anon_delete'
        )
      )
  loop
    execute format('drop policy if exists %I on %I.%I', pol.policyname, pol.schemaname, pol.tablename);
  end loop;
end $$;

-- mosque_admins
drop policy if exists "admins_read_own" on public.mosque_admins;
drop policy if exists "admins_update_own" on public.mosque_admins;
drop policy if exists "admins_select_mosque" on public.mosque_admins;

create policy "admins_select_own_mosque"
  on public.mosque_admins for select to authenticated
  using (
    auth_user_id = (select auth.uid())
    or id = (select auth.uid())
    or mosque_id = (select public.current_admin_mosque_id())
  );

create policy "admins_update_own"
  on public.mosque_admins for update to authenticated
  using (
    auth_user_id = (select auth.uid())
    or id = (select auth.uid())
  )
  with check (
    auth_user_id = (select auth.uid())
    or id = (select auth.uid())
  );

-- mosques
drop policy if exists "mosques_select_authenticated_admin" on public.mosques;
drop policy if exists "mosques_insert_via_rpc" on public.mosques;
drop policy if exists "mosques_read_member" on public.mosques;
drop policy if exists "mosques_admin_select" on public.mosques;
drop policy if exists "mosques_admin_update" on public.mosques;

create policy "mosques_admin_select"
  on public.mosques for select to authenticated
  using (id = (select public.current_admin_mosque_id()));

create policy "mosques_admin_update"
  on public.mosques for update to authenticated
  using (id = (select public.current_admin_mosque_id()))
  with check (id = (select public.current_admin_mosque_id()));

-- teachers / students / sessions / attendance / homework / progress
drop policy if exists "teachers_admin_all" on public.teachers;
create policy "teachers_admin_all"
  on public.teachers for all to authenticated
  using (mosque_id = (select public.current_admin_mosque_id()))
  with check (mosque_id = (select public.current_admin_mosque_id()));

drop policy if exists "students_admin_all" on public.students;
create policy "students_admin_all"
  on public.students for all to authenticated
  using (mosque_id = (select public.current_admin_mosque_id()))
  with check (mosque_id = (select public.current_admin_mosque_id()));

drop policy if exists "sessions_admin_select" on public.sessions;
drop policy if exists "sessions_admin_all" on public.sessions;
create policy "sessions_admin_all"
  on public.sessions for all to authenticated
  using (mosque_id = (select public.current_admin_mosque_id()))
  with check (mosque_id = (select public.current_admin_mosque_id()));

drop policy if exists "attendance_admin_select" on public.attendance;
drop policy if exists "attendance_admin_all" on public.attendance;
create policy "attendance_admin_all"
  on public.attendance for all to authenticated
  using (
    session_id in (
      select id from public.sessions
      where mosque_id = (select public.current_admin_mosque_id())
    )
  )
  with check (
    session_id in (
      select id from public.sessions
      where mosque_id = (select public.current_admin_mosque_id())
    )
  );

drop policy if exists "homework_admin_select" on public.student_homework;
drop policy if exists "homework_admin_all" on public.student_homework;
create policy "homework_admin_all"
  on public.student_homework for all to authenticated
  using (
    student_id in (
      select id from public.students
      where mosque_id = (select public.current_admin_mosque_id())
    )
  )
  with check (
    student_id in (
      select id from public.students
      where mosque_id = (select public.current_admin_mosque_id())
    )
  );

drop policy if exists "progress_admin_select" on public.progress;
drop policy if exists "progress_admin_all" on public.progress;
create policy "progress_admin_all"
  on public.progress for all to authenticated
  using (
    student_id in (
      select id from public.students
      where mosque_id = (select public.current_admin_mosque_id())
    )
  )
  with check (
    student_id in (
      select id from public.students
      where mosque_id = (select public.current_admin_mosque_id())
    )
  );

-- registration / sessions tables: no direct client access (Edge Functions use service_role)
drop policy if exists "reg_requests_no_direct" on public.mosque_registration_requests;
-- intentionally no policies for anon/authenticated → deny by default under RLS

-- platform_sessions / actor_sessions: service_role only (bypass RLS)
-- no policies for anon/authenticated

revoke all on public.platform_sessions from anon, authenticated;
revoke all on public.actor_sessions from anon, authenticated;
revoke all on public.mosque_registration_requests from anon, authenticated;

grant select, insert, update, delete on all tables in schema public to service_role;
grant usage on schema private to postgres, service_role;
