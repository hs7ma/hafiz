/// قواعد نص المصحف والصوت في تطبيق حافظ (رواية حفص عن عاصم / مصحف المدينة)
/// كما يعتمدها مشروع تنزيل Tanzil.
///
/// 1) الفاتحة: البسملة هي الآية رقم 1 من أصل 7 آيات — تُعرض وتُشغَّل كآية.
/// 2) التوبة: لا بسملة إطلاقًا.
/// 3) بقية السور: البسملة للافتتاح/العرض فقط وليست آية معدودة.
///    الآية 1 = أول آية بعد البسملة (مثل البقرة: الٓمٓ).
/// 4) مجموع الآيات المعدودة = 6236.
/// 5) تحذير صوتي: كثير من ملفات EveryAyah/CDN لآية 1 (غير الفاتحة)
///    تبدأ بتسجيل البسملة ثم نص الآية؛ لذلك نتخطى مدة البسملة عند التشغيل.
class QuranRules {
  static bool isFatiha(int surah) => surah == 1;
  static bool isTawbah(int surah) => surah == 9;

  /// هل البسملة آية معدودة في هذه السورة؟
  static bool bismillahIsAyah(int surah) => isFatiha(surah);

  /// هل يُعرض سطر بسملة غير معدود أعلى السورة؟
  static bool showsDisplayBismillah(int surah) =>
      !isFatiha(surah) && !isTawbah(surah);

  /// هل تسجيل آية 1 غالبًا يبدأ بالبسملة في ملفات التلاوة الشائعة؟
  static bool ayahOneAudioOftenStartsWithBasmala(int surah) =>
      showsDisplayBismillah(surah);
}
