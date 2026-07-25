/// مصادر صوت مجانية لتلاوة القرآن (بدون مفتاح API).
///
/// الرابط الأساسي EveryAyah بصيغة SSSAAA = سورة:آية صريحة
/// لتجنب أي التباس مع الترقيم العالمي، والاحتياطي هو cdn.islamic.network
/// بالترقيم العالمي. المصدران يقدّمان نفس التسجيلات لنفس القرّاء، لذلك
/// لكل قارئ معرّفان: مجلد EveryAyah وإصدار الـ CDN المقابل له.
class QuranReciter {
  const QuranReciter({
    required this.id,
    required this.nameAr,
    required this.everyAyahFolder,
    required this.cdnEdition,
  });

  final String id;
  final String nameAr;

  /// اسم المجلد على everyayah.com.
  final String everyAyahFolder;

  /// إصدار نفس القارئ على cdn.islamic.network — يضمن أن المصدر الاحتياطي
  /// لا يبدّل صوت القارئ في منتصف التلاوة.
  final String cdnEdition;
}

class QuranAudioSources {
  static const reciters = <QuranReciter>[
    QuranReciter(
      id: 'alafasy',
      nameAr: 'مشاري العفاسي',
      everyAyahFolder: 'Alafasy_128kbps',
      cdnEdition: 'ar.alafasy',
    ),
    QuranReciter(
      id: 'minshawy',
      nameAr: 'محمد صديق المنشاوي',
      everyAyahFolder: 'Minshawy_Murattal_128kbps',
      cdnEdition: 'ar.minshawi',
    ),
    QuranReciter(
      id: 'husary',
      nameAr: 'محمود خليل الحصري',
      everyAyahFolder: 'Husary_128kbps',
      cdnEdition: 'ar.husary',
    ),
    QuranReciter(
      id: 'shaatree',
      nameAr: 'أبو بكر الشاطري',
      everyAyahFolder: 'Abu_Bakr_Ash-Shaatree_128kbps',
      cdnEdition: 'ar.shaatree',
    ),
  ];

  static QuranReciter byId(String id) {
    return reciters.firstWhere(
      (r) => r.id == id,
      orElse: () => reciters.first,
    );
  }

  /// EveryAyah: سورة/آية صراحةً (SSSAAA).
  static String everyAyahUrl(
    QuranReciter reciter,
    int surahNumber,
    int ayahNumber,
  ) {
    final s = surahNumber.toString().padLeft(3, '0');
    final a = ayahNumber.toString().padLeft(3, '0');
    return 'https://everyayah.com/data/${reciter.everyAyahFolder}/$s$a.mp3';
  }

  /// احتياطي CDN بالرقم العالمي 1..6236 وبنفس القارئ المختار.
  static String islamicNetworkUrl(QuranReciter reciter, int globalAyah) {
    return 'https://cdn.islamic.network/quran/audio/128/'
        '${reciter.cdnEdition}/$globalAyah.mp3';
  }

  static List<String> urlsFor({
    required QuranReciter reciter,
    required int surahNumber,
    required int ayahNumber,
    required int globalAyah,
  }) {
    // EveryAyah أولًا لأنه يطابق رقم السورة/الآية حرفيًا.
    return [
      everyAyahUrl(reciter, surahNumber, ayahNumber),
      islamicNetworkUrl(reciter, globalAyah),
    ];
  }
}
