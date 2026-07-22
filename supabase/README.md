# خلفية حافظ على Supabase

الخلفية الوحيدة للتطبيق: Postgres + Edge Functions على Supabase.

## المكوّنات

| جزء | الدور |
| --- | --- |
| `migrations/` | مخطط الجداول + RLS + دوال `private` و RPC العامة |
| `functions/hafiz-api` | API (تسجيل من التطبيق، موافقة، دخول، طلاب، مزامنة) |
| `functions/serve-register` | رسالة JSON: التسجيل من داخل التطبيق |
| `functions/serve-platform` | رسالة JSON: استخدم تطبيق `platform_app` |

> ملاحظة: Supabase لا يعرض HTML على نطاقه. تسجيل الجوامع داخل تطبيق حافظ، وإدارة المنصة في تطبيق `platform_app` المنفصل.

## الأسرار (Edge Function secrets)

لا تضع `service_role` في Flutter أو صفحات الويب. اضبط في المشروع:

```bash
npx supabase secrets set PLATFORM_ADMIN_PASSWORD="your-long-password"
```

تُحقن تلقائيًا في الدوال: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`.

## تطبيق المخطط

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

## عناوين بعد النشر

- إدارة المنصة: https://qlqzdtphwmoohqgqftuv.supabase.co/functions/v1/serve-platform
- API: https://qlqzdtphwmoohqgqftuv.supabase.co/functions/v1/hafiz-api/

## Flutter

```bash
flutter run
```

الافتراضي في التطبيق يتصل بمشروع hafiz عبر مفتاح anon. لتجاوز الإعدادات استخدم `--dart-define`.

## أمان

- RLS مفعّل على جداول `public`؛ عمليات المنصة والمزامنة عبر `service_role` داخل Edge فقط.
- صلاحيات المسؤول في `app_metadata` عند إنشاء مستخدم Auth (ليست `user_metadata`).
- دوال مساعدة حسّاسة في مخطط `private`.
- سياسات `anon` الواسعة القديمة تُحذف في الهجرة.
