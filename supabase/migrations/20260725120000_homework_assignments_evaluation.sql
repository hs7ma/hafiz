-- أرشيف الواجبات السابقة + تأكيد التقييم
alter table attendance
  add column if not exists evaluation_confirmed_at timestamptz;

create table if not exists homework_assignments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references students(id) on delete cascade,
  session_id uuid references sessions(id) on delete set null,
  surah_number int not null,
  from_ayah int not null,
  to_ayah int not null,
  note text not null default '',
  assigned_at timestamptz not null default now()
);

create index if not exists homework_assignments_student_id_idx
  on homework_assignments(student_id);

create index if not exists homework_assignments_assigned_at_idx
  on homework_assignments(assigned_at desc);
