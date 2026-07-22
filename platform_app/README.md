# حافظ — إدارة المنصة

تطبيق Flutter منفصل لمراجعة طلبات تسجيل الجوامع (موافقة / رفض).

لا يُضمَّن داخل تطبيق المساجد `hafiz`.

## التشغيل

```bash
cd platform_app
flutter pub get
flutter run -d windows
# أو: flutter run -d chrome
# أو: flutter run  (جهاز Android)
```

يتصل تلقائياً بمشروع Supabase `qlqzdtphwmoohqgqftuv`.

## الاستخدام

1. أدخل كلمة مرور إدارة المنصة (`PLATFORM_ADMIN_PASSWORD` في أسرار Edge Functions)
2. راجع الطلبات قيد المراجعة
3. وافق (يُنشأ حساب المسجد وتُفتح واتساب) أو ارفض
