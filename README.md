# حافظ

تطبيق Flutter لتنظيم حضور وحفظ طلبة دورات تحفيظ القرآن في المساجد.
يعمل **أوفلاين أولًا**: يحفظ على الجهاز ثم يزامن مع خادم Node.js + SQLite عند توفر الشبكة.

## التشغيل السريع

```bash
cd hafiz
flutter pub get
flutter run
```

الافتراضي يتصل بمحاكي Android عبر `http://10.0.2.2:3000`.  
للتعطيل الكامل للمزامنة: `--dart-define=API_BASE_URL=`

## خادم Node.js (SQLite)

```bash
cd server
npm install
npm start
```

- قاعدة البيانات: `server/data/hafiz.sqlite`
- كلمات المرور: bcrypt
- راجع `server/README.md`

### ربط الهاتف الحقيقي

عند تشغيل الخادم سيظهر IP الشبكة. مثال:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:3000
```

### بناء APK

```bash
flutter build apk --release --dart-define=API_BASE_URL=http://192.168.1.10:3000
```

الملف: `build/app/outputs/flutter-apk/app-release.apk`

نسخة جاهزة لتيليجرام: `releases/hafiz-release.apk`

## سلوك المزامنة الأوفلاين

1. كل عملية تُحفظ فورًا محليًا (SharedPreferences)
2. تُضاف إلى طابور مزامنة
3. عند الاتصال: `POST /api/sync/push` ثم سحب لقطة المسجد
4. `connectivity_plus` يعيد المحاولة عند عودة الشبكة

## حسابات التجربة

| الدور | الدخول |
|--------|---------|
| مسؤول | مسجد النور / admin@demo.local / demo1234 |
| مدرّس | الشيخ إبراهيم / IB482917 |
| طالب | ahmad_yusuf / A7K3M |

## هيكل المشروع

```
lib/          تطبيق Flutter (أوفلاين + مزامنة)
server/       Express + better-sqlite3
supabase/     مخطط مرجعي قديم (غير مستخدم كخلفية تشغيل)
```
