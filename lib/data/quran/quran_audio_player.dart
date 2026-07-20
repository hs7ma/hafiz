import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'quran_audio.dart';
import 'quran_repository.dart';

/// وضع الاستماع: آية واحدة أو تشغيل متواصل (كلي) لنطاق الآيات.
enum ListenMode { singleAyah, continuous }

class QuranAudioPlayer {
  QuranAudioPlayer(this._quran);

  final QuranRepository _quran;
  AudioPlayer _player = AudioPlayer();

  QuranReciter reciter = QuranAudioSources.reciters.first;
  ListenMode mode = ListenMode.continuous;

  int? currentSurah;
  int? currentAyah;
  int? rangeStart;
  int? rangeEnd;

  /// هل النطاق المتواصل ما زال نشطًا (يستأنف بعد الإيقاف المؤقت).
  bool rangeActive = false;

  StreamSubscription<PlayerState>? _stateSub;
  void Function(int surah, int ayah)? _onAyahChanged;
  void Function()? _onStateChanged;

  /// رمز يميّز كل طلب تشغيل لإلغاء الطلبات القديمة عند الضغط السريع.
  int _playToken = 0;

  /// حارس يمنع تكرار الانتقال التلقائي للآية التالية أكثر من مرة.
  bool _advancing = false;

  bool get isPlaying => _player.playing;

  bool get isPaused =>
      currentAyah != null &&
      !isPlaying &&
      _player.processingState != ProcessingState.idle &&
      _player.processingState != ProcessingState.completed;

  bool get hasSession => currentSurah != null && currentAyah != null;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;

  void ensureListeners({
    void Function(int surah, int ayah)? onAyahChanged,
    void Function()? onStateChanged,
  }) {
    if (onAyahChanged != null) _onAyahChanged = onAyahChanged;
    if (onStateChanged != null) _onStateChanged = onStateChanged;
    _bindStateListener();
  }

  void _notifyState() => _onStateChanged?.call();

  void _bindStateListener() {
    _stateSub?.cancel();
    final player = _player;
    _stateSub = player.playerStateStream.listen((state) async {
      // تجاهل أحداث مشغّل قديم لم يعد هو المشغّل الحالي.
      if (player != _player) return;
      _notifyState();
      if (!rangeActive || mode != ListenMode.continuous) return;
      if (state.processingState != ProcessingState.completed) return;
      if (_advancing) return;
      final surah = currentSurah;
      final ayah = currentAyah;
      final end = rangeEnd;
      if (surah == null || ayah == null || end == null) return;
      if (ayah >= end) {
        rangeActive = false;
        _notifyState();
        return;
      }
      _advancing = true;
      try {
        final next = ayah + 1;
        await playAyah(surah, next, keepRange: true);
        _onAyahChanged?.call(surah, next);
      } finally {
        _advancing = false;
      }
    });
  }

  Future<void> _resetPlayer() async {
    await _stateSub?.cancel();
    _stateSub = null;
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _player.dispose();
    } catch (_) {}
    _player = AudioPlayer();
    _bindStateListener();
  }

  /// يشغّل آية معيّنة من بدايتها تمامًا.
  ///
  /// نُنشئ مشغّلًا جديدًا لكل آية ونضبط الموضع الابتدائي على الصفر، ثم نتحقق
  /// من الرمز [_playToken] قبل كل خطوة لتفادي تداخل التشغيل عند الضغط السريع.
  Future<void> playAyah(
    int surah,
    int ayah, {
    bool keepRange = false,
  }) async {
    final token = ++_playToken;
    if (!keepRange) {
      rangeActive = false;
      rangeStart = null;
      rangeEnd = null;
    }

    final urls = _quran.audioUrls(
      surahNumber: surah,
      ayahNumber: ayah,
      reciter: reciter,
    );

    await _resetPlayer();
    if (token != _playToken) return;
    final player = _player;

    Object? lastError;
    for (final url in urls) {
      if (token != _playToken || player != _player) return;
      try {
        // preload + initialPosition=0 يضمنان بدء التلاوة من أول الآية دائمًا.
        await player.setAudioSource(
          AudioSource.uri(
            Uri.parse(url),
            tag: 's${surah}_a${ayah}_$token',
          ),
          initialPosition: Duration.zero,
        );
        if (token != _playToken || player != _player) return;
        // تأكيد إضافي أن الموضع عند الصفر بعد اكتمال التحميل.
        if (player.processingState != ProcessingState.idle &&
            player.processingState != ProcessingState.loading) {
          await player.seek(Duration.zero);
        }
        if (token != _playToken || player != _player) return;
        currentSurah = surah;
        currentAyah = ayah;
        _notifyState();
        await player.play();
        _notifyState();
        return;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('تعذر تشغيل التلاوة');
  }

  /// تشغيل بسملة الافتتاح وحدها (ليست آية إلا في الفاتحة).
  Future<void> playOpeningBasmala() async {
    rangeActive = false;
    rangeStart = null;
    rangeEnd = null;
    await playAyah(1, 1);
    currentSurah = null;
    currentAyah = null;
    _notifyState();
  }

  Future<void> playRange(int surah, int fromAyah, int toAyah) async {
    mode = ListenMode.continuous;
    rangeActive = true;
    rangeStart = fromAyah;
    rangeEnd = toAyah;
    await playAyah(surah, fromAyah, keepRange: true);
  }

  /// تشغيل آية ضمن نطاق الواجب (وضع آية واحدة أو بداية كلي).
  Future<void> playHomework({
    required int surah,
    required int fromAyah,
    required int toAyah,
    int? startAyah,
  }) async {
    final start = (startAyah ?? fromAyah).clamp(fromAyah, toAyah);
    rangeStart = fromAyah;
    rangeEnd = toAyah;
    rangeActive = mode == ListenMode.continuous;
    await playAyah(surah, start, keepRange: true);
  }

  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (_) {}
    _notifyState();
  }

  /// يستأنف من موضع الإيقاف المؤقت نفسه؛ أما إن كانت الآية قد انتهت فيبدأ
  /// الآية التالية (في الوضع الكلي) أو يعيد الآية الحالية من بدايتها.
  Future<void> resume() async {
    if (!hasSession) return;
    try {
      if (_player.processingState == ProcessingState.completed) {
        final surah = currentSurah!;
        final ayah = currentAyah!;
        if (mode == ListenMode.continuous &&
            rangeEnd != null &&
            ayah < rangeEnd!) {
          rangeActive = true;
          await playAyah(surah, ayah + 1, keepRange: true);
          _onAyahChanged?.call(surah, ayah + 1);
          return;
        }
        await playAyah(surah, ayah, keepRange: rangeActive || rangeEnd != null);
        return;
      }
      await _player.play();
    } catch (_) {}
    _notifyState();
  }

  Future<void> stop() async {
    rangeActive = false;
    _advancing = false;
    _playToken++;
    try {
      await _player.stop();
    } catch (_) {}
    currentSurah = null;
    currentAyah = null;
    _notifyState();
  }

  Future<void> toggleAyah(int surah, int ayah) async {
    if (currentSurah == surah && currentAyah == ayah) {
      if (isPlaying) {
        await pause();
        return;
      }
      if (isPaused) {
        await resume();
        return;
      }
    }
    mode = ListenMode.singleAyah;
    rangeActive = false;
    rangeStart = null;
    rangeEnd = null;
    await playAyah(surah, ayah);
  }

  /// الانتقال لآية سابقة/تالية ضمن النطاق — تبدأ دائمًا من بداية الآية الجديدة.
  Future<void> playAdjacent({required bool next}) async {
    final surah = currentSurah;
    final ayah = currentAyah;
    if (surah == null || ayah == null) return;

    final start = rangeStart ?? 1;
    final end = rangeEnd ?? _quran.surahByNumber(surah).ayahCount;
    final target = next ? ayah + 1 : ayah - 1;
    if (target < start || target > end) return;

    if (mode == ListenMode.continuous) {
      rangeActive = true;
    }
    await playAyah(surah, target, keepRange: rangeEnd != null);
    _onAyahChanged?.call(surah, target);
  }

  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
    } catch (_) {}
    _notifyState();
  }

  Future<void> dispose() async {
    rangeActive = false;
    _advancing = false;
    _playToken++;
    await _stateSub?.cancel();
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
