# خلفية حافظ على Supabase

هذا المجلد هو المسار المعتمد للخلفية بعد الهجرة من Express/Railway.

## المكوّنات

| جزء | الدور |
| --- | --- |
| `migrations/` | مخطط الجداول + RLS + دوال `private` و RPC العامة |
| `functions/hafiz-api` | بديل مسارات Express (تسجيل، موافقة، دخول، طلاب، مزامنة) |
| `functions/serve-register` | صفحة `/register` كـ HTML من Edge |
| `functions/serve-platform` | صفحة `/platform` كـ HTML من Edge |

## الأسرار (Edge Function secrets)

لا تضع `service_role` في Flutter أو صفحات الويب. اضبط في المشروع:

```bash
npx supabase secrets set PLATFORM_ADMIN_PASSWORD="your-long-password"
```

تُحقن تلقائيًا في الدوال: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`.

## تطبيق المخطط

بعد مصادقة Supabase MCP أو ربط CLI:

```bash
npx supabase link --project-ref qlqzdtphwmoohqgqftuv
npx supabase db push
# أو نفّذ ملف الهجرة يدويًا من SQL Editor
```

ثم انشر الدوال:

```bash
npx supabase functions deploy hafiz-api --no-verify-jwt
npx supabase functions deploy serve-register --no-verify-jwt
npx supabase functions deploy serve-platform --no-verify-jwt
```

## عناوين الصفحات بعد النشر

- تسجيل جامع: `https://<ref>.supabase.co/functions/v1/serve-register`
- إدارة المنصة: `https://<ref>.supabase.co/functions/v1/serve-platform`
- API: `https://<ref>.supabase.co/functions/v1/hafiz-api/...`

## Flutter

```bash
flutter run ^
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co ^
  --dart-define=SUPABASE_ANON_KEY=<anon-or-publishable-key> ^
  --dart-define=API_BASE_URL=
```

`API_BASE_URL=` يعطّل احتياطي Railway. التطبيق يستدعي Edge Function `hafiz-api` بمفتاح anon فقط ويخزّن `hafiz_token` بعد الدخول.

## أمان

- RLS مفعّل على جداول `public`؛ عمليات المنصة والمزامنة عبر `service_role` داخل Edge فقط.
- صلاحيات المسؤول في `app_metadata` عند إنشاء مستخدم Auth (ليست `user_metadata`).
- دوال مساعدة حسّاسة في مخطط `private`.
- سياسات `anon` الواسعة القديمة تُحذف في الهجرة.

## إيقاف Railway

بعد التحقق من Edge + Flutter:

1. انقل DNS/الروابط من `hafiz.up.railway.app` إلى دوال Supabase.
2. أوقف خدمة Railway.
3. أبقِ `server/` مؤقتًا كمرجع ثم احذفه لاحقًا.

## متبقٍ / TODO

- [ ] تطبيق الهجرة على المشروع السحابي (يتطلب MCP auth أو `supabase link`)
- [ ] نشر الدوال وضبط `PLATFORM_ADMIN_PASSWORD`
- [ ] ربط حسابات `mosque_admins` الحالية بـ Auth (يتم تلقائيًا عند أول دخول ناجح)
- [ ] تضييق أكثر لجلسات المدرّس/الطالب (مدة أقصر / إلغاء عند الحاجة)
- [ ] Advisors أمني بعد الدفع
