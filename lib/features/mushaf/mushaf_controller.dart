import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mushaf_prefs.dart';

/// السورة المعروضة حاليًا في المصحف (تصفح حر عبر الفهرس).
class MushafSurahController extends Notifier<int> {
  static bool _restoredOnce = false;

  @override
  int build() => 1;

  void open(int surahNumber) {
    state = surahNumber.clamp(1, 114);
    unawaited(MushafPrefs.saveLastSurah(state));
  }

  /// استرجاع آخر سورة مفتوحة عند أول دخول للمصحف في الجلسة.
  Future<void> restoreLastOpened() async {
    if (_restoredOnce) return;
    _restoredOnce = true;
    final saved = await MushafPrefs.lastSurah();
    if (saved != null && state == 1) {
      state = saved.clamp(1, 114);
    }
  }
}

final mushafSurahProvider =
    NotifierProvider<MushafSurahController, int>(MushafSurahController.new);
