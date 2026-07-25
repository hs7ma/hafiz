-- مواعيد دروس المدرّس الأسبوعية (قالب أيام الحلقة)

create table if not exists public.teacher_class_schedules (
  id uuid primary key default gen_random_uuid(),
  mosque_id uuid not null references public.mosques(id) on delete cascade,
  teacher_id uuid not null references public.teachers(id) on delete cascade,
  lectures_per_week int not null check (lectures_per_week between 1 and 7),
  -- أيام الأسبوع وفق ISO/Dart: 1=اثنين … 7=أحد
  weekdays int[] not null,
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  constraint teacher_class_schedules_weekdays_len
    check (cardinality(weekdays) = lectures_per_week),
  constraint teacher_class_schedules_weekdays_range
    check (
      weekdays <@ array[1, 2, 3, 4, 5, 6, 7]::int[]
    ),
  unique (teacher_id)
);

create index if not exists teacher_class_schedules_mosque_idx
  on public.teacher_class_schedules (mosque_id);

alter table public.teacher_class_schedules enable row level security;

drop policy if exists "teacher_class_schedules_admin_all" on public.teacher_class_schedules;
create policy "teacher_class_schedules_admin_all"
  on public.teacher_class_schedules
  for all
  using (public.is_mosque_admin() and mosque_id = public.current_admin_mosque_id())
  with check (public.is_mosque_admin() and mosque_id = public.current_admin_mosque_id());

grant select, insert, update, delete on public.teacher_class_schedules to service_role;
