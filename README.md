# حافظ

تطبيق Flutter لتنظيم حضور وحفظ طلبة دورات تحفيظ القرآن في المساجد.
يعمل **أوفلاين أولًا**: يحفظ على الجهاز ثم يزامن مع **Supabase** (Edge Functions + Postgres).

## التشغيل السريع

```bash
flutter pub get
flutter run ^
  --dart-define=SUPABASE_URL=https://YOUR_REF.supabase.co ^
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY ^
  --dart-define=API_BASE_URL=
```

التفاصيل الكاملة للهجرة والنشر: [`supabase/README.md`](supabase/README.md)

## خلفية Express/Railway (قديم — قيد الإيقاف)

المجلد `server/` كان يخدم نفس قاعدة Supabase Postgres عبر Express على Railway.
بعد اكتمال الهجرة يُستبدل بـ Edge Functions. راجع ملاحظات الإيقاف في `server/README.md`.

## بناء APK

```bash
flutter build apk --release ^
  --dart-define=SUPABASE_URL=https://YOUR_REF.supabase.co ^
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY ^
  --dart-define=API_BASE_URL=
```

الملف: `build/app/outputs/flutter-apk/app-release.apk`

## سلوك المزامنة الأوفلاين

1. كل عملية تُحفظ فورًا محليًا (SharedPreferences)
2. تُضاف إلى طابور مزامنة
3. عند الاتصال: `POST .../hafiz-api/sync/push` ثم سحب لقطة المسجد
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
supabase/     Migrations + Edge Functions (المسار المعتمد)
server/       Express القديم (احتياطي أثناء الانتقال)
```
