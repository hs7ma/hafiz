import 'quran_rules.dart';

/// مصادر صوت مجانية لتلاوة القرآن (بدون مفتاح API).
///
/// الرابط الأساسي EveryAyah بصيغة SSSAAA = سورة:آية صريحة
/// لتجنب أي التباس مع الترقيم العالمي.
class QuranReciter {
  const QuranReciter({
    required this.id,
    required this.nameAr,
    required this.everyAyahFolder,
    required this.basmalaSkip,
  });

  final String id;
  final String nameAr;
  final String everyAyahFolder;

  /// مدة تقريبية لبسملة هذا القارئ (لتخطيها في آية 1 لغير الفاتحة).
  final Duration basmalaSkip;
}

class QuranAudioSources {
  static const reciters = <QuranReciter>[
    QuranReciter(
      id: 'alafasy',
      nameAr: 'مشاري العفاسي',
      everyAyahFolder: 'Alafasy_128kbps',
      basmalaSkip: Duration(milliseconds: 6000),
    ),
    QuranReciter(
      id: 'minshawy',
      nameAr: 'محمد صديق المنشاوي',
      everyAyahFolder: 'Minshawy_Murattal_128kbps',
      basmalaSkip: Duration(milliseconds: 5200),
    ),
    QuranReciter(
      id: 'husary',
      nameAr: 'محمود خليل الحصري',
      everyAyahFolder: 'Husary_128kbps',
      basmalaSkip: Duration(milliseconds: 5500),
    ),
    QuranReciter(
      id: 'shaatree',
      nameAr: 'أبو بكر الشاطري',
      everyAyahFolder: 'Abu_Bakr_Ash-Shaatree_128kbps',
      basmalaSkip: Duration(milliseconds: 5800),
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

  /// احتياطي CDN بالرقم العالمي 1..6236.
  static String islamicNetworkUrl(int globalAyah) {
    return 'https://cdn.islamic.network/quran/audio/128/ar.alafasy/$globalAyah.mp3';
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
      islamicNetworkUrl(globalAyah),
    ];
  }

  static Duration? introSkip({
    required QuranReciter reciter,
    required int surahNumber,
    required int ayahNumber,
  }) {
    if (ayahNumber != 1) return null;
    if (!QuranRules.ayahOneAudioOftenStartsWithBasmala(surahNumber)) {
      return null;
    }
    return reciter.basmalaSkip;
  }
}
