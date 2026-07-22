-- Secure teacher invite registration (short-lived single-use codes)

create table if not exists public.teacher_invites (
  id uuid primary key default gen_random_uuid(),
  mosque_id uuid not null references public.mosques(id) on delete cascade,
  code_hash text not null,
  registration_token_hash text,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  failed_attempts int not null default 0,
  created_by_admin_id uuid references public.mosque_admins(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists teacher_invites_mosque_idx
  on public.teacher_invites (mosque_id, created_at desc);
create index if not exists teacher_invites_code_hash_idx
  on public.teacher_invites (code_hash);
create index if not exists teacher_invites_reg_token_idx
  on public.teacher_invites (registration_token_hash)
  where registration_token_hash is not null;

alter table public.teachers
  add column if not exists email text,
  add column if not exists password_hash text,
  add column if not exists auth_user_id uuid unique references auth.users(id) on delete set null,
  add column if not exists whatsapp_phone text;

create unique index if not exists teachers_email_unique_idx
  on public.teachers (lower(email))
  where email is not null and email <> '';

alter table public.teacher_invites enable row level security;
drop policy if exists "teacher_invites_no_direct" on public.teacher_invites;
create policy "teacher_invites_no_direct"
  on public.teacher_invites for all using (false) with check (false);
revoke all on public.teacher_invites from anon, authenticated;
