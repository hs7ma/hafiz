-- حافظ | مخطط قاعدة بيانات Supabase (مستأجر المسجد)
-- نفّذ هذا الملف كاملًا في SQL Editor داخل مشروعك على Supabase
-- يمكن إعادة التشغيل بأمان (idempotent قدر الإمكان)

create extension if not exists "pgcrypto";

do $$ begin
  create type user_role as enum ('mosque_admin', 'teacher', 'student');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type attendance_status as enum ('unmarked', 'present', 'absent', 'late');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type session_status as enum ('active', 'completed', 'cancelled');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type memorization_level as enum (
    'not_memorized',
    'poor',
    'average',
    'good',
    'very_good',
    'excellent'
  );
exception when duplicate_object then null;
end $$;

create table if not exists public.mosques (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now(),
  unique (name)
);

-- إدارة الجامع (مرتبطة بـ auth.users عند الربط الحقيقي)
create table if not exists public.mosque_admins (
  id uuid primary key references auth.users(id) on delete cascade,
  mosque_id uuid not null references public.mosques(id) on delete cascade,
  full_name text not null,
  email text not null,
  created_at timestamptz not null default now(),
  unique (email)
);

-- المدرّسون: دخول بالاسم + الرمز (حرفان إنجليزيان + 6 أرقام)
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

-- الطلبة: دخول باسم مستخدم + رمز 5–8
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
  status session_status not null default 'active',
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  unique (teacher_id, session_date)
);

create table if not exists public.attendance (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  status attendance_status not null default 'unmarked',
  memorization_level memorization_level,
  behavior_score int check (behavior_score is null or (behavior_score between 0 and 10)),
  marked_at timestamptz,
  unique (session_id, student_id)
);

-- واجب فردي لكل طالب
create table if not exists public.student_homework (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  surah_number int not null check (surah_number between 1 and 114),
  from_ayah int not null check (from_ayah >= 1),
  to_ayah int not null check (to_ayah >= from_ayah),
  note text default '',
  assigned_at timestamptz not null default now(),
  unique (student_id)
);

create table if not exists public.progress (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  surah_number int not null check (surah_number between 1 and 114),
  ayah_number int not null check (ayah_number >= 1),
  updated_at timestamptz not null default now(),
  unique (student_id)
);

create index if not exists idx_teachers_mosque on public.teachers (mosque_id);
create index if not exists idx_teachers_login on public.teachers (full_name, login_code);
create index if not exists idx_students_teacher on public.students (teacher_id);
create index if not exists idx_students_login on public.students (login_username, login_code);
create index if not exists idx_sessions_teacher_date on public.sessions (teacher_id, session_date);
create index if not exists idx_attendance_session on public.attendance (session_id);
create index if not exists idx_homework_student on public.student_homework (student_id);

alter table public.mosques enable row level security;
alter table public.mosque_admins enable row level security;
alter table public.teachers enable row level security;
alter table public.students enable row level security;
alter table public.sessions enable row level security;
alter table public.attendance enable row level security;
alter table public.student_homework enable row level security;
alter table public.progress enable row level security;

-- ---------------------------------------------------------------------------
-- دوال مساعدة للهوية (مسؤول المسجد عبر Auth، مدرّس/طالب عبر الرموز)
-- ---------------------------------------------------------------------------

create or replace function public.current_admin_mosque_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select mosque_id from public.mosque_admins where id = auth.uid()
$$;

create or replace function public.is_mosque_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.mosque_admins where id = auth.uid())
$$;

-- تسجيل مسجد + مسؤول (يُستدعى بعد supabase.auth.signUp)
create or replace function public.register_mosque_admin(
  p_mosque_name text,
  p_admin_name text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_mosque public.mosques%rowtype;
begin
  if v_uid is null then
    raise exception 'يجب تسجيل الدخول أولاً';
  end if;

  select email into v_email from auth.users where id = v_uid;
  if v_email is null then
    raise exception 'حساب المستخدم غير موجود';
  end if;

  if exists (select 1 from public.mosque_admins where id = v_uid) then
    raise exception 'هذا الحساب مسجّل كمسؤول مسبقًا';
  end if;

  if exists (select 1 from public.mosques where name = trim(p_mosque_name)) then
    raise exception 'يوجد مسجد بهذا الاسم مسبقًا';
  end if;

  insert into public.mosques (name)
  values (trim(p_mosque_name))
  returning * into v_mosque;

  insert into public.mosque_admins (id, mosque_id, full_name, email)
  values (v_uid, v_mosque.id, trim(p_admin_name), lower(v_email));

  return json_build_object(
    'mosque_id', v_mosque.id,
    'mosque_name', v_mosque.name,
    'admin_id', v_uid,
    'email', lower(v_email)
  );
end;
$$;

-- دخول المدرّس بالاسم + الرمز (بدون Auth JWT)
create or replace function public.login_teacher(
  p_full_name text,
  p_login_code text
)
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
    'mosque_name', v_mosque_name
  );
end;
$$;

-- دخول الطالب باسم المستخدم + الرمز
create or replace function public.login_student(
  p_username text,
  p_login_code text
)
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
    'mosque_name', v_mosque_name
  );
end;
$$;

grant execute on function public.current_admin_mosque_id() to anon, authenticated;
grant execute on function public.is_mosque_admin() to anon, authenticated;
grant execute on function public.register_mosque_admin(text, text) to authenticated;
grant execute on function public.login_teacher(text, text) to anon, authenticated;
grant execute on function public.login_student(text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- سياسات RLS
-- جسر تجريبي→إنتاج: مسؤول المسجد عبر Auth؛ المدرّس/الطالب عبر الرموز + سياسات anon للقراءة/الكتابة التشغيلية
-- Tightening لاحقًا: ربط جلسات المدرّس/الطالب بـ JWT مخصّص أو Edge Functions
-- ---------------------------------------------------------------------------

drop policy if exists "admins_read_own" on public.mosque_admins;
drop policy if exists "admins_read_own_mosque" on public.mosque_admins;
drop policy if exists "admins_insert_self" on public.mosque_admins;
drop policy if exists "admins_update_own" on public.mosque_admins;

create policy "admins_read_own" on public.mosque_admins
  for select using (auth.uid() = id);

create policy "admins_update_own" on public.mosque_admins
  for update using (auth.uid() = id);

drop policy if exists "mosques_read_member" on public.mosques;
drop policy if exists "mosques_insert_authenticated" on public.mosques;
drop policy if exists "mosques_select_all_for_login" on public.mosques;

-- قراءة المساجد للأعضاء + للدخول بالرموز (anon) أثناء مرحلة الاختبار
create policy "mosques_select_authenticated_admin" on public.mosques
  for select to authenticated
  using (id = public.current_admin_mosque_id());

create policy "mosques_select_anon_bridge" on public.mosques
  for select to anon
  using (true);

create policy "mosques_insert_via_rpc" on public.mosques
  for insert to authenticated
  with check (true);

-- المدرّسون
drop policy if exists "teachers_admin_all" on public.teachers;
drop policy if exists "teachers_anon_select" on public.teachers;
drop policy if exists "teachers_anon_write_bridge" on public.teachers;

create policy "teachers_admin_all" on public.teachers
  for all to authenticated
  using (mosque_id = public.current_admin_mosque_id())
  with check (mosque_id = public.current_admin_mosque_id());

-- جسر الاختبار: anon يقرأ/يكتب بيانات الحلقة (المدرّس يدخل بالرمز من التطبيق)
create policy "teachers_anon_select" on public.teachers
  for select to anon using (true);

create policy "teachers_anon_insert" on public.teachers
  for insert to anon with check (true);

create policy "teachers_anon_update" on public.teachers
  for update to anon using (true) with check (true);

create policy "teachers_anon_delete" on public.teachers
  for delete to anon using (true);

-- الطلبة
drop policy if exists "students_admin_all" on public.students;
drop policy if exists "students_anon_bridge" on public.students;

create policy "students_admin_all" on public.students
  for all to authenticated
  using (mosque_id = public.current_admin_mosque_id())
  with check (mosque_id = public.current_admin_mosque_id());

create policy "students_anon_select" on public.students
  for select to anon using (true);

create policy "students_anon_insert" on public.students
  for insert to anon with check (true);

create policy "students_anon_update" on public.students
  for update to anon using (true) with check (true);

create policy "students_anon_delete" on public.students
  for delete to anon using (true);

-- الجلسات
drop policy if exists "sessions_admin_all" on public.sessions;
drop policy if exists "sessions_anon_bridge" on public.sessions;

create policy "sessions_admin_select" on public.sessions
  for select to authenticated
  using (mosque_id = public.current_admin_mosque_id());

create policy "sessions_anon_select" on public.sessions
  for select to anon using (true);

create policy "sessions_anon_insert" on public.sessions
  for insert to anon with check (true);

create policy "sessions_anon_update" on public.sessions
  for update to anon using (true) with check (true);

create policy "sessions_anon_delete" on public.sessions
  for delete to anon using (true);

-- الحضور
drop policy if exists "attendance_admin_all" on public.attendance;
drop policy if exists "attendance_anon_bridge" on public.attendance;

create policy "attendance_admin_select" on public.attendance
  for select to authenticated
  using (
    session_id in (
      select id from public.sessions
      where mosque_id = public.current_admin_mosque_id()
    )
  );

create policy "attendance_anon_select" on public.attendance
  for select to anon using (true);

create policy "attendance_anon_insert" on public.attendance
  for insert to anon with check (true);

create policy "attendance_anon_update" on public.attendance
  for update to anon using (true) with check (true);

create policy "attendance_anon_delete" on public.attendance
  for delete to anon using (true);

-- الواجبات
drop policy if exists "homework_admin_all" on public.student_homework;
drop policy if exists "homework_anon_bridge" on public.student_homework;

create policy "homework_admin_select" on public.student_homework
  for select to authenticated
  using (
    student_id in (
      select id from public.students
      where mosque_id = public.current_admin_mosque_id()
    )
  );

create policy "homework_anon_select" on public.student_homework
  for select to anon using (true);

create policy "homework_anon_insert" on public.student_homework
  for insert to anon with check (true);

create policy "homework_anon_update" on public.student_homework
  for update to anon using (true) with check (true);

create policy "homework_anon_delete" on public.student_homework
  for delete to anon using (true);

-- التقدّم
drop policy if exists "progress_admin_all" on public.progress;
drop policy if exists "progress_anon_bridge" on public.progress;

create policy "progress_admin_select" on public.progress
  for select to authenticated
  using (
    student_id in (
      select id from public.students
      where mosque_id = public.current_admin_mosque_id()
    )
  );

create policy "progress_anon_select" on public.progress
  for select to anon using (true);

create policy "progress_anon_insert" on public.progress
  for insert to anon with check (true);

create policy "progress_anon_update" on public.progress
  for update to anon using (true) with check (true);

create policy "progress_anon_delete" on public.progress
  for delete to anon using (true);

-- ملاحظة أمنية: سياسات anon أعلاه مخصّصة لمرحلة الاختبار الحقيقي عبر مفتاح anon من التطبيق.
-- قبل الإنتاج العام: أزل سياسات anon الواسعة واعتمد جلسات موقّعة أو Edge Functions.
