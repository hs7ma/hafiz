# خادم حافظ (Node.js + Supabase Postgres) — قيد الإيقاف

> **هجرة جارية:** الخلفية المستهدفة هي Supabase Edge Functions في [`../supabase/`](../supabase/).
> أبقِ هذا الخادم يعمل على Railway حتى يكتمل النشر والتحقق، ثم أوقفه.

API للمزامنة الأوفلاين: Express على Railway، وقاعدة البيانات على **Supabase Postgres**.

## التشغيل المحلي

```bash
cd server
cp .env.example .env
npm install
npm start
```

الصحة: `curl http://127.0.0.1:3000/health`

## متغيرات البيئة

| المتغير | الوصف |
|---------|--------|
| `DATABASE_URL` | رابط Postgres (Pooler مفضّل) |
| `PLATFORM_ADMIN_PASSWORD` | كلمة مرور صفحة `/platform` |
| `PORT` | على Railway تلقائي |

> لا ترفع ملف `.env` إلى Git.

## إيقاف Railway (بعد نجاح Supabase)

1. انشر migrations + Edge Functions (`hafiz-api`, `serve-register`, `serve-platform`)
2. اضبط `PLATFORM_ADMIN_PASSWORD` كـ Edge secret
3. حدّث Flutter إلى `SUPABASE_URL` + `SUPABASE_ANON_KEY` و`API_BASE_URL=`
4. اختبر: تسجيل → موافقة → دخول → مزامنة
5. أوقف خدمة Railway

## مسارات Express (يقابلها `hafiz-api`)

انظر الجدول في المستودع الجذر / `supabase/README.md`.
