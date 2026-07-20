# خادم حافظ (Node.js + SQLite)

API محلي لتجربة التطبيق الحقيقي ومزامنة البيانات من الأجهزة الأوفلاين.

## المتطلبات

- Node.js 18 أو أحدث
- أدوات بناء أصلية لـ `better-sqlite3` (على Windows غالبًا كافية مع Node الرسمي)

## التشغيل

```bash
cd server
npm install
npm start
```

الخادم يستمع على المنفذ `3000` افتراضيًا (أو `PORT` من البيئة).

بعد التشغيل ستظهر عناوين:

- `http://127.0.0.1:3000` — من نفس الجهاز
- `http://10.0.2.2:3000` — من محاكي Android إلى جهاز المضيف
- `http://192.168.x.x:3000` — من الهاتف على نفس شبكة Wi‑Fi

تحقق سريع:

```bash
curl http://127.0.0.1:3000/health
```

### إعادة زرع بيانات التجربة

```bash
npm run seed
```

## حسابات التجربة (تُزرع تلقائيًا عند أول تشغيل)

| الدور | الدخول |
|--------|---------|
| مسؤول | مسجد النور / `admin@demo.local` / `demo1234` |
| مدرّس | الشيخ إبراهيم / `IB482917` |
| طالب | `ahmad_yusuf` / `A7K3M` |

## ربط التطبيق (Flutter)

محاكي Android (الافتراضي في التطبيق):

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

هاتف حقيقي على نفس الشبكة — استبدل IP بعنوان جهازك كما يظهر عند تشغيل الخادم:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:3000
```

بناء APK:

```bash
flutter build apk --release --dart-define=API_BASE_URL=http://192.168.1.10:3000
```

الملف: `build/app/outputs/flutter-apk/app-release.apk`

## النشر على Railway

جذر المستودع هنا هو مشروع Flutter، والخادم موجود داخل مجلد `server/`.
لذلك عند النشر على Railway يجب ضبط **Root Directory** للخدمة على `server`.

### 1) إعداد الخدمة

- في إعدادات الخدمة على Railway اضبط **Root Directory = `server`**.
- سيكتشف Railway مشروع Node تلقائيًا ويبني عبر **Nixpacks**
  (موجود أيضًا صراحةً في `server/railway.json`).
- أمر التشغيل: `npm start` (معرّف في `railway.json` وفي `package.json`).
- المنفذ `PORT` تضبطه Railway تلقائيًا — **لا تحدده يدويًا** ولا تكتبه في الكود.

### 2) قاعدة البيانات الدائمة (مهم جدًا)

نظام ملفات حاويات Railway **مؤقّت (ephemeral)**؛ أي ملف SQLite محلي **سيُمحى**
مع كل إعادة نشر أو إعادة تشغيل ما لم يُخزَّن على **Volume** دائم.

- أنشئ **Volume** وثبّته على المسار `/data`.
- أضف متغيّر البيئة: `DATA_DIR=/data`.

عندها يقرأ الخادم مجلد التخزين من `DATA_DIR` (انظر `src/db.js`) وتبقى
قاعدة `hafiz.sqlite` محفوظة بين عمليات النشر. راجع `.env.example` للمتغيرات.

### 3) طرق النشر

طريقتان (لا تنفّذ أوامر النشر إن كنت تُجهّز فقط):

- **(أ) ربط مستودع GitHub:** ادفع المشروع إلى GitHub ثم من Railway اختر
  *New Project → Deploy from GitHub repo*، واضبط Root Directory على `server`.
  كل دفعة (push) تُطلق نشرًا جديدًا تلقائيًا.
- **(ب) عبر Railway CLI:** من داخل مجلد `server`:

```bash
railway up
```

### 4) التحقق بعد النشر

- افتح الرابط العام: `https://<your-app>.up.railway.app/health` ويجب أن يعيد
  `{"ok":true,...}`.
- عنوان الـ API هو نفس الرابط الأساسي **بدون** لاحقة `/api`
  (تطبيق Flutter يضيف `/api` تلقائيًا في `lib/data/remote/api_client.dart`).

### 5) ربط تطبيق Flutter بالخادم على Railway

أعد بناء التطبيق مع تمرير عنوان الخادم (بدون `/api` وبدون شرطة مائلة في النهاية):

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://<your-app>.up.railway.app
```

مثال تشغيل مباشر:

```bash
flutter run --dart-define=API_BASE_URL=https://<your-app>.up.railway.app
```

## التخزين

- قاعدة SQLite: `server/data/hafiz.sqlite` محليًا، أو داخل `DATA_DIR` إن ضُبط
  (على Railway: `/data` عبر Volume دائم).
- كلمات مرور المسؤول مُجزّأة بـ bcrypt
- احذف الملف أو شغّل `npm run seed` لإعادة البداية

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
| POST | `/api/sync/push` | دفع طابور المزامنة من الجهاز |
| GET | `/api/sync/pull?mosque_id=` | سحب لقطة المسجد |

عمليات المزامنة تدعم UUID من العميل (idempotent قدر الإمكان).

## ملاحظات أمنية

هذا الخادم مخصّص للتجربة على شبكة محلية. لا تعرضه على الإنترنت العام بدون مصادقة أقوى وHTTPS.
