import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';

/// أوضاع قراءة المصحف: فاتح، سيبيا دافئ، ليلي.
enum MushafTheme { light, sepia, dark }

extension MushafThemeX on MushafTheme {
  String get labelAr => switch (this) {
        MushafTheme.light => 'فاتح',
        MushafTheme.sepia => 'سيبيا',
        MushafTheme.dark => 'ليلي',
      };

  IconData get icon => switch (this) {
        MushafTheme.light => Icons.light_mode_outlined,
        MushafTheme.sepia => Icons.auto_stories_outlined,
        MushafTheme.dark => Icons.dark_mode_outlined,
      };
}

/// ألوان صفحة المصحف حسب وضع القراءة.
class MushafPalette {
  const MushafPalette({
    required this.background,
    required this.border,
    required this.text,
    required this.accent,
    required this.subtle,
    required this.playingBg,
    required this.homeworkBg,
    required this.markerFill,
  });

  final Color background;
  final Color border;
  final Color text;
  final Color accent;
  final Color subtle;
  final Color playingBg;
  final Color homeworkBg;
  final Color markerFill;

  static MushafPalette of(MushafTheme theme) => switch (theme) {
        MushafTheme.light => const MushafPalette(
            background: Color(0xFFFBF6EA),
            border: Color(0xFFE3D5B5),
            text: AppColors.ink,
            accent: AppColors.oliveDark,
            subtle: Color(0x8C5B5545),
            playingBg: AppColors.softGreen,
            homeworkBg: Color(0x40E8C56A),
            markerFill: Color(0xFFFDFAF1),
          ),
        MushafTheme.sepia => const MushafPalette(
            background: Color(0xFFF1E2C3),
            border: Color(0xFFD9C39A),
            text: Color(0xFF463823),
            accent: Color(0xFF6B5427),
            subtle: Color(0x99584A2E),
            playingBg: Color(0x66B9CBA0),
            homeworkBg: Color(0x55DCA94E),
            markerFill: Color(0xFFF7EDD6),
          ),
        MushafTheme.dark => const MushafPalette(
            background: Color(0xFF1F251E),
            border: Color(0xFF3B463C),
            text: Color(0xFFE9E4D2),
            accent: Color(0xFFD9C68C),
            subtle: Color(0x99BCB69F),
            playingBg: Color(0x3D6E9A6C),
            homeworkBg: Color(0x38D9AE55),
            markerFill: Color(0xFF2A322A),
          ),
      };
}

/// تفضيلات القراءة المحفوظة محليًا (حجم الخط، الوضع، القارئ، آخر موضع).
class MushafPrefs {
  static const _kFontSize = 'mushaf_font_size_v1';
  static const _kTheme = 'mushaf_theme_v1';
  static const _kReciter = 'mushaf_reciter_v1';
  static const _kLastSurah = 'mushaf_last_surah_v1';
  static const _kScrollPrefix = 'mushaf_scroll_v1_';

  static const double minFontSize = 22;
  static const double maxFontSize = 40;
  static const double defaultFontSize = 28;

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  static Future<double> fontSize() async =>
      ((await _prefs).getDouble(_kFontSize) ?? defaultFontSize)
          .clamp(minFontSize, maxFontSize);

  static Future<void> saveFontSize(double size) async =>
      (await _prefs).setDouble(_kFontSize, size);

  static Future<MushafTheme> theme() async {
    final name = (await _prefs).getString(_kTheme);
    return MushafTheme.values.firstWhere(
      (t) => t.name == name,
      orElse: () => MushafTheme.light,
    );
  }

  static Future<void> saveTheme(MushafTheme theme) async =>
      (await _prefs).setString(_kTheme, theme.name);

  static Future<String?> reciterId() async =>
      (await _prefs).getString(_kReciter);

  static Future<void> saveReciterId(String id) async =>
      (await _prefs).setString(_kReciter, id);

  static Future<int?> lastSurah() async => (await _prefs).getInt(_kLastSurah);

  static Future<void> saveLastSurah(int surah) async =>
      (await _prefs).setInt(_kLastSurah, surah);

  static Future<double?> scrollOffset(int surah) async =>
      (await _prefs).getDouble('$_kScrollPrefix$surah');

  static Future<void> saveScrollOffset(int surah, double offset) async =>
      (await _prefs).setDouble('$_kScrollPrefix$surah', offset);
}
