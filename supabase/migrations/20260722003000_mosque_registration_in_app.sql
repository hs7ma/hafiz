-- In-app mosque registration: address (Iraq), capacity ranges, email verification link

alter table public.mosque_registration_requests
  add column if not exists governorate text,
  add column if not exists district text,
  add column if not exists area text,
  add column if not exists students_range text,
  add column if not exists teachers_range text,
  add column if not exists email_verified_at timestamptz,
  add column if not exists auth_user_id uuid;

alter table public.mosques
  add column if not exists governorate text,
  add column if not exists district text,
  add column if not exists area text,
  add column if not exists students_range text,
  add column if not exists teachers_range text;

create index if not exists mosque_registration_requests_auth_user_idx
  on public.mosque_registration_requests (auth_user_id);

-- Replace public RPC with extended fields (Iraq phone default 964)
drop function if exists public.submit_registration_request(text, text, text);

create or replace function public.submit_registration_request(
  p_mosque_name text,
  p_email text,
  p_whatsapp_phone text,
  p_governorate text default null,
  p_district text default null,
  p_area text default null,
  p_students_range text default null,
  p_teachers_range text default null
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
  v_gov text := nullif(trim(coalesce(p_governorate, '')), '');
  v_dist text := nullif(trim(coalesce(p_district, '')), '');
  v_area text := nullif(trim(coalesce(p_area, '')), '');
  v_students text := nullif(trim(coalesce(p_students_range, '')), '');
  v_teachers text := nullif(trim(coalesce(p_teachers_range, '')), '');
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
    v_phone := '964' || substr(v_phone, 2);
  end if;
  if v_gov is null or v_dist is null or v_area is null then
    raise exception 'أدخل عنوان المسجد كاملاً';
  end if;
  if v_students is null or v_teachers is null then
    raise exception 'حدد عدد الطلاب والمدرّسين';
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

  insert into public.mosque_registration_requests (
    mosque_name, email, whatsapp_phone, status,
    governorate, district, area, students_range, teachers_range
  ) values (
    v_name, v_email, v_phone, 'pending',
    v_gov, v_dist, v_area, v_students, v_teachers
  )
  returning * into v_row;

  return json_build_object(
    'request', json_build_object(
      'id', v_row.id,
      'mosque_name', v_row.mosque_name,
      'email', v_row.email,
      'whatsapp_phone', v_row.whatsapp_phone,
      'governorate', v_row.governorate,
      'district', v_row.district,
      'area', v_row.area,
      'students_range', v_row.students_range,
      'teachers_range', v_row.teachers_range,
      'status', v_row.status,
      'mosque_id', v_row.mosque_id,
      'reviewed_at', v_row.reviewed_at,
      'created_at', v_row.created_at
    ),
    'message', 'تم إرسال الطلب. انتظر موافقة إدارة حافظ.'
  );
end;
$$;

grant execute on function public.submit_registration_request(
  text, text, text, text, text, text, text, text
) to anon, authenticated;
