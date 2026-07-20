# خادم حافظ (Node.js + Supabase Postgres)

API للمزامنة الأوفلاين: Express على Railway، وقاعدة البيانات على **Supabase Postgres**.

## المتطلبات

- Node.js 18 أو أحدث
- مشروع Supabase مع جداول التطبيق (يُنشئها الخادم تلقائيًا عند التشغيل إن لزم)

## التشغيل المحلي

```bash
cd server
cp .env.example .env
# املأ DATABASE_URL من Supabase (يفضّل Connection pooling / Transaction)
npm install
npm start
```

الصحة: `curl http://127.0.0.1:3000/health`  
المتوقع: `"engine":"postgres"`

### إعادة زرع بيانات التجربة

```bash
npm run seed
```

## حسابات التجربة

| الدور | الدخول |
|--------|---------|
| مسؤول | مسجد النور / `admin@demo.local` / `demo1234` |
| مدرّس | الشيخ إبراهيم / `IB482917` |
| طالب | `ahmad_yusuf` / `A7K3M` |

## متغيرات البيئة

| المتغير | الوصف |
|---------|--------|
| `DATABASE_URL` | رابط Postgres (Pooler مفضّل على الشبكات بدون IPv6) |
| `SUPABASE_DB_PASSWORD` | بديل إن لم تضبط `DATABASE_URL` |
| `SUPABASE_PROJECT_REF` | معرّف المشروع (افتراضي من إعدادكم) |
| `SUPABASE_REGION` | منطقة الـ pooler مثل `ap-southeast-2` |
| `PORT` | على Railway تلقائي |

مثال Pooler (Transaction / منفذ 6543):

```
postgresql://postgres.<PROJECT_REF>:<PASSWORD>@aws-0-<REGION>.pooler.supabase.com:6543/postgres
```

> لا ترفع ملف `.env` إلى Git. ضعه في Railway Variables فقط.

## النشر على Railway

1. **Root Directory** = `server`
2. أزل الاعتماد على Volume/SQLite إن وُجد (`DATA_DIR` لم يعد مطلوبًا)
3. أضف المتغير:

```
DATABASE_URL=postgresql://postgres.<REF>:<PASSWORD>@aws-0-<REGION>.pooler.supabase.com:6543/postgres
```

4. انشر، ثم افتح: `https://<app>.up.railway.app/health`

## ربط Flutter

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://<your-app>.up.railway.app
```

## أهم المسارات

| Method | Path | الوصف |
|--------|------|--------|
| POST | `/api/auth/register` | تسجيل مسجد + مسؤول |
| POST | `/api/auth/login` | دخول مسؤول |
| POST | `/api/auth/teacher-login` | دخول مدرّس بالرمز |
| POST | `/api/auth/student-login` | دخول طالب بالرمز |
| GET/POST | `/api/teachers` | قائمة / إنشاء مدرّسين |
| GET/POST | `/api/students` | قائمة / إنشاء طلبة |
| POST | `/api/sessions/start` | بدء محاضرة اليوم |
| PUT | `/api/attendance/:id` | تحديث حضور/حفظ/سلوك |
| PUT | `/api/homework/:studentId` | تعيين واجب |
| POST | `/api/sync/push` | دفع طابور المزامنة |
| GET | `/api/sync/pull?mosque_id=` | سحب لقطة المسجد |
