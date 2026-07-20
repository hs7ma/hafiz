import 'dart:convert';

import 'package:flutter/services.dart';

import 'quran_audio.dart';

class SurahMeta {
  const SurahMeta({
    required this.number,
    required this.name,
    required this.ayahCount,
  });

  final int number;
  final String name;
  final int ayahCount;
}

class QuranMetadata {
  const QuranMetadata({
    required this.source,
    required this.version,
    required this.website,
    required this.ayahTotal,
  });

  final String source;
  final String version;
  final String website;
  final int ayahTotal;
}

/// مستودع المصحف — نص عثماني حرفي من مشروع تنزيل (Tanzil).
/// لا يُعدَّل نص الآيات نهائيًا بعد التحميل.
class QuranRepository {
  List<SurahMeta> _surahs = const [];
  Map<String, List<String>> _ayahs = const {};
  Map<String, String> _bismillah = const {};
  List<int> _globalOffsetBySurah = const [];
  QuranMetadata? metadata;

  Future<void> load() async {
    final raw =
        await rootBundle.loadString('assets/quran/quran_tanzil_uthmani.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;

    final meta = json['metadata'] as Map<String, dynamic>;
    metadata = QuranMetadata(
      source: meta['source'] as String? ?? 'Tanzil Project',
      version: meta['version'] as String? ?? 'Uthmani',
      website: meta['website'] as String? ?? 'https://tanzil.net',
      ayahTotal: meta['expectedAyahTotal'] as int? ?? 6236,
    );

    _surahs = (json['surahs'] as List)
        .map(
          (e) => SurahMeta(
            number: e['number'] as int,
            name: e['name'] as String,
            ayahCount: e['ayahCount'] as int,
          ),
        )
        .toList();

    // نصوص الآيات كما وردت من Tanzil دون أي تعديل على الأحرف.
    _ayahs = (json['ayahs'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, List<String>.from(value as List)),
    );
    _bismillah = (json['bismillah'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(key, value as String),
    );

    var total = 0;
    for (final s in _surahs) {
      final list = _ayahs['${s.number}'] ?? const [];
      if (list.length != s.ayahCount) {
        throw StateError(
          'تحقق المصحف فشل: السورة ${s.number} العدد ${list.length}/${s.ayahCount}',
        );
      }
      total += list.length;
    }
    if (total != 6236) {
      throw StateError('تحقق المصحف فشل: مجموع الآيات $total بدل 6236');
    }

    final offsets = List<int>.filled(115, 0);
    var running = 1;
    for (final surah in _surahs) {
      offsets[surah.number] = running;
      running += surah.ayahCount;
    }
    _globalOffsetBySurah = offsets;
  }

  List<SurahMeta> get surahs => _surahs;

  SurahMeta surahByNumber(int number) {
    return _surahs.firstWhere((s) => s.number == number);
  }

  List<String> ayahsOf(int surahNumber) {
    return _ayahs['$surahNumber'] ?? const [];
  }

  /// بسملة العرض أعلى السورة (ليست آية معدودة) — عدا الفاتحة والتوبة.
  String? bismillahOf(int surahNumber) => _bismillah['$surahNumber'];

  String? ayahText(int surahNumber, int ayahNumber) {
    final list = ayahsOf(surahNumber);
    if (ayahNumber < 1 || ayahNumber > list.length) return null;
    return list[ayahNumber - 1];
  }

  int globalAyahNumber(int surahNumber, int ayahNumber) {
    if (surahNumber < 1 || surahNumber > 114) {
      throw RangeError('surahNumber out of range');
    }
    return _globalOffsetBySurah[surahNumber] + ayahNumber - 1;
  }

  List<String> audioUrls({
    required int surahNumber,
    required int ayahNumber,
    QuranReciter? reciter,
  }) {
    final chosen = reciter ?? QuranAudioSources.reciters.first;
    return QuranAudioSources.urlsFor(
      reciter: chosen,
      surahNumber: surahNumber,
      ayahNumber: ayahNumber,
      globalAyah: globalAyahNumber(surahNumber, ayahNumber),
    );
  }

  static String audioUrl(int surahNumber, int ayahNumber) {
    return QuranAudioSources.everyAyahUrl(
      QuranAudioSources.byId('alafasy'),
      surahNumber,
      ayahNumber,
    );
  }
}
