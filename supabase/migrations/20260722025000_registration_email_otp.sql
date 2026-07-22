-- OTP مستقل عن قوالب Supabase Auth / قيود Resend الافتراضية.
create table if not exists public.registration_email_otps (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  code_hash text not null,
  -- يظهر لإدارة المنصة فقط عند فشل الإرسال التلقائي (TTL قصير)
  code_plain text,
  delivery text not null default 'email'
    check (delivery in ('email', 'manual')),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_registration_email_otps_email
  on public.registration_email_otps (email, created_at desc);

alter table public.registration_email_otps enable row level security;

drop policy if exists "registration_email_otps_no_direct" on public.registration_email_otps;
create policy "registration_email_otps_no_direct"
  on public.registration_email_otps
  for all
  using (false)
  with check (false);

create table if not exists public.registration_proofs (
  token text primary key,
  email text not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

alter table public.registration_proofs enable row level security;
drop policy if exists "registration_proofs_no_direct" on public.registration_proofs;
create policy "registration_proofs_no_direct"
  on public.registration_proofs
  for all
  using (false)
  with check (false);
