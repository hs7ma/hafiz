# حافظ

تطبيق Flutter لتنظيم حضور وحفظ طلبة دورات تحفيظ القرآن في المساجد.
يعمل **أوفلاين أولًا** ويُزامن مع **Supabase** (Edge Functions + Postgres).

## التشغيل

```bash
flutter pub get
flutter run
```

الافتراضي يتصل بمشروع Supabase `qlqzdtphwmoohqgqftuv` عبر مفتاح anon المضمّن.
لا حاجة لـ Railway.

## الصفحات العامة

- تسجيل جامع: https://qlqzdtphwmoohqgqftuv.supabase.co/functions/v1/serve-register
- إدارة المنصة: https://qlqzdtphwmoohqgqftuv.supabase.co/functions/v1/serve-platform

## بناء APK

```bash
flutter build apk --release
```

الملف: `releases/hafiz.apk` (بعد النسخ من مخرجات البناء)

## حسابات التجربة

| الدور | الدخول |
|--------|---------|
| مسؤول | مسجد النور / admin@demo.local / demo1234 |
| مدرّس | الشيخ إبراهيم / IB482917 |
| طالب | ahmad_yusuf / A7K3M |

## هيكل المشروع

```
lib/          تطبيق Flutter
supabase/     Migrations + Edge Functions (المسار المعتمد)
server/       Express القديم (مرجع فقط — يمكن إيقاف Railway)
```

التفاصيل: [`supabase/README.md`](supabase/README.md)
