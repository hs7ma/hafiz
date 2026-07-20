import 'dart:convert';

import 'package:flutter/services.dart';

/// التفسير الميسر — مجمع الملك فهد (أوفلاين).
class TafsirMuyassarRepository {
  Map<String, String> _ayahs = const {};
  TafsirMetadata? metadata;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final raw =
        await rootBundle.loadString('assets/quran/tafsir_muyassar.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final meta = json['metadata'] as Map<String, dynamic>? ?? {};
    metadata = TafsirMetadata(
      source: meta['source'] as String? ?? 'التفسير الميسر',
      identifier: meta['identifier'] as String? ?? 'ar-tafsir-muyassar',
      note: meta['note'] as String? ?? '',
    );
    _ayahs = (json['ayahs'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, value as String),
    );
    _loaded = true;
  }

  String? of(int surahNumber, int ayahNumber) {
    if (!_loaded) return null;
    return _ayahs['$surahNumber:$ayahNumber'];
  }
}

class TafsirMetadata {
  const TafsirMetadata({
    required this.source,
    required this.identifier,
    required this.note,
  });

  final String source;
  final String identifier;
  final String note;
}
