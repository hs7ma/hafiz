import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'quran_audio.dart';
import 'quran_repository.dart';

/// وضع الاستماع: آية واحدة أو تشغيل متواصل (كلي) لنطاق الآيات.
enum ListenMode { singleAyah, continuous }

enum QuranPlaybackStatus { idle, loading, playing, paused, completed, failed }

/// حدود جلسة الاستماع: السورة وأول/آخر آية يجوز للمشغّل الوصول إليها.
///
/// النطاق هو واجب اليوم إن وُجد على السورة المعروضة، وإلا فالسورة كاملة.
class ListenBounds {
  const ListenBounds({
    required this.surah,
    required this.from,
    required this.to,
  });

  final int surah;
  final int from;
  final int to;

  int get length => to - from + 1;

  bool contains(int ayah) => ayah >= from && ayah <= to;

  int clampAyah(int ayah) {
    if (ayah < from) return from;
    if (ayah > to) return to;
    return ayah;
  }

  @override
  bool operator ==(Object other) =>
      other is ListenBounds &&
      other.surah == surah &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(surah, from, to);

  @override
  String toString() => 'ListenBounds(surah: $surah, $from–$to)';
}

/// مشغّل التلاوة: مشغّل واحد دائم تُبنى داخله قائمة تشغيل للنطاق كاملًا.
///
/// تحميل الآيات كقائمة واحدة يجعل `just_audio` يجهّز الآية التالية أثناء
/// تشغيل الحالية، فينتقل بينها بلا فجوة صمت، ويحوّل التقديم والتأخير إلى
/// `seek` فوري بدل إعادة تحميل من الشبكة.
///
/// ملاحظتان تحكمان تصميم هذا الصنف:
/// * `AudioPlayer.play()` يعيد `Future` لا يكتمل إلا بانتهاء التلاوة، فلا
///   يجوز انتظاره وإلا تجمّدت الواجهة طوال الآية.
/// * حالة العرض تُشتق من نية المستخدم [_wantPlaying] لا من حالة المشغّل
///   اللحظية، حتى لا تومض الأزرار كلما دخل المشغّل في التحميل.
class QuranAudioPlayer {
  QuranAudioPlayer(
    this._quran, {
    AudioPlayer? player,
    QuranReciter? initialReciter,
    ListenMode initialMode = ListenMode.continuous,
  }) : _player = player ?? AudioPlayer(),
       _reciter = initialReciter ?? QuranAudioSources.reciters.first,
       _mode = initialMode {
    _bindStreams();
  }

  /// عدد المصادر البديلة لكل آية (EveryAyah ثم cdn.islamic.network).
  static const _sourceTiers = 2;

  final QuranRepository _quran;
  final AudioPlayer _player;

  QuranReciter _reciter;
  ListenMode _mode;

  ListenBounds? _bounds;

  /// حدود القائمة المحمّلة فعليًا: تساوي [_bounds] في الوضع الكلي، وتساوي
  /// آية واحدة في وضع الآية المفردة.
  int _listFrom = 0;
  int _listTo = 0;

  int? _currentAyah;

  /// المصدر المستخدم حاليًا (0 = EveryAyah، 1 = CDN)؛ يتصاعد عند الفشل.
  int _tier = 0;

  /// نية المستخدم: هل يريد سماع الصوت الآن؟ منفصلة عن حالة المشغّل الفعلية
  /// حتى لا يُلغي تحميلٌ متأخّر ضغطةَ إيقاف مؤقت سبقته.
  bool _wantPlaying = false;

  bool _loading = false;
  bool _disposed = false;
  bool _completed = false;
  String? _errorMessage;

  /// هل القائمة المحمّلة تطابق [_listFrom]/[_listTo] الحاليين؟
  ///
  /// أثناء إعادة البناء تبقى القائمة القديمة قائمة لحظةً، فلو ترجمنا فهرسها
  /// بالحدود الجديدة لأعلنّا آية خاطئة أو ابتلعنا نية التشغيل بحدث «اكتمل»
  /// قديم. لذلك نتجاهل أحداث المشغّل حتى تجهز القائمة الجديدة.
  bool _listReady = false;

  int _loadToken = 0;
  Future<void> _chain = Future<void>.value();

  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<int?>? _indexSub;
  StreamSubscription<PlayerException>? _errorSub;

  void Function(int surah, int ayah)? _onAyahChanged;
  void Function()? _onStateChanged;

  QuranReciter get reciter => _reciter;
  ListenMode get mode => _mode;

  ListenBounds? get bounds => _bounds;
  int? get currentSurah => _bounds?.surah;
  int? get currentAyah => _currentAyah;
  int? get rangeStart => _bounds?.from;
  int? get rangeEnd => _bounds?.to;

  bool get hasSession => _bounds != null && _currentAyah != null;
  QuranPlaybackStatus get status {
    if (!hasSession) return QuranPlaybackStatus.idle;
    if (_errorMessage != null) return QuranPlaybackStatus.failed;
    if (_completed) return QuranPlaybackStatus.completed;
    if (_loading) return QuranPlaybackStatus.loading;
    return _wantPlaying
        ? QuranPlaybackStatus.playing
        : QuranPlaybackStatus.paused;
  }

  String? get errorMessage => _errorMessage;
  bool get isCompleted => hasSession && _completed;
  bool get hasError => hasSession && _errorMessage != null;

  /// «يعمل الآن» من منظور المستخدم — يشمل لحظات التحميل حتى لا يتحول زر
  /// الإيقاف المؤقت إلى زر تشغيل بين كل آيتين.
  bool get isPlaying => hasSession && _wantPlaying;

  bool get isPaused =>
      hasSession && !_wantPlaying && !_completed && _errorMessage == null;

  /// للعرض فقط (مؤشّر انتظار)؛ لا يُستعمل لتعطيل أزرار التحكم.
  bool get isBuffering =>
      hasSession &&
      (_loading ||
          _player.processingState == ProcessingState.loading ||
          _player.processingState == ProcessingState.buffering);

  bool get canNext {
    final bounds = _bounds;
    final ayah = _currentAyah;
    return bounds != null && ayah != null && ayah < bounds.to;
  }

  bool get canPrev {
    final bounds = _bounds;
    final ayah = _currentAyah;
    return bounds != null && ayah != null && ayah > bounds.from;
  }

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
  }

  void _notify() {
    if (_disposed) return;
    _onStateChanged?.call();
  }

  void _announceAyah(int surah, int ayah) {
    if (_disposed) return;
    _onAyahChanged?.call(surah, ayah);
  }

  void _markFailed([Object? error]) {
    if (_disposed) return;
    _wantPlaying = false;
    _loading = false;
    _completed = false;
    _errorMessage = 'تعذّر تشغيل التلاوة. تحقق من الإنترنت ثم أعد المحاولة.';
    _notify();
  }

  void _playWithoutBlocking() {
    unawaited(
      _player.play().catchError((Object error, StackTrace stackTrace) {
        _markFailed(error);
      }),
    );
  }

  void _bindStreams() {
    // انتقال القائمة للعنصر التالي يصل هنا لحظة حدوثه، فتتابعه الواجهة
    // فورًا بدل أن تتأخر إلى ما بعد انتهاء الآية.
    _indexSub = _player.currentIndexStream.listen((index) {
      if (_disposed || index == null || !_listReady) return;
      final bounds = _bounds;
      if (bounds == null) return;
      final ayah = _listFrom + index;
      if (ayah < _listFrom || ayah > _listTo) return;
      if (ayah == _currentAyah) return;
      _currentAyah = ayah;
      _announceAyah(bounds.surah, ayah);
      _notify();
    });

    _stateSub = _player.playerStateStream.listen((state) {
      if (_disposed) return;
      // اكتمال القائمة يعني نهاية النطاق (أو نهاية الآية في الوضع المفرد).
      // نتجاهله أثناء إعادة البناء لئلا يُلغي حدثٌ قديم تشغيلًا جديدًا.
      if (state.processingState == ProcessingState.completed &&
          _listReady &&
          !_loading) {
        _wantPlaying = false;
        _completed = true;
        _errorMessage = null;
      }
      _notify();
    });

    _errorSub = _player.errorStream.listen(_onPlayerError);
  }

  /// فشل عنصر داخل القائمة أثناء التشغيل (مصدر محجوب أو انقطاع شبكة):
  /// نعيد بناء القائمة من الآية نفسها بالمصدر التالي بدل توقّف الجلسة بصمت.
  void _onPlayerError(PlayerException error) {
    if (_disposed || _loading) return;
    final bounds = _bounds;
    if (bounds == null) return;
    final index = error.index;
    final failed = index == null ? _currentAyah : _listFrom + index;
    if (failed == null || !bounds.contains(failed)) return;
    if (_tier >= _sourceTiers - 1) {
      _markFailed(error);
      return;
    }
    _tier++;
    final resumePlaying = _wantPlaying;
    unawaited(
      _serial(() => _load(failed, play: resumePlaying)).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        _markFailed(error);
      }),
    );
  }

  /// يسلسل عمليات المشغّل حتى لا يتداخل تحميلان، أو تحميلٌ مع إيقاف.
  Future<void> _serial(Future<void> Function() action) {
    final result = _chain.then((_) => action());
    _chain = result.then((_) {}, onError: (_) {});
    return result;
  }

  List<AudioSource> _sourcesFor(int surah, int from, int to, int tier) {
    final sources = <AudioSource>[];
    final surahName = _quran.surahByNumber(surah).name;
    for (var ayah = from; ayah <= to; ayah++) {
      final urls = _quran.audioUrls(
        surahNumber: surah,
        ayahNumber: ayah,
        reciter: _reciter,
      );
      final url = urls[tier.clamp(0, urls.length - 1)];
      sources.add(
        AudioSource.uri(
          Uri.parse(url),
          tag: MediaItem(
            id: '${_reciter.id}:$surah:$ayah',
            album: 'القرآن الكريم • ${_reciter.nameAr}',
            title: 'سورة $surahName • الآية $ayah',
          ),
        ),
      );
    }
    return sources;
  }

  /// يبني قائمة التشغيل ويضع المؤشّر على [startAyah].
  ///
  /// يجب استدعاؤه دائمًا داخل [_serial].
  Future<void> _load(
    int startAyah, {
    Duration initialPosition = Duration.zero,
    required bool play,
  }) async {
    final bounds = _bounds;
    if (bounds == null || _disposed) return;

    final token = ++_loadToken;
    final start = bounds.clampAyah(startAyah);
    final continuous = _mode == ListenMode.continuous;

    _listFrom = continuous ? bounds.from : start;
    _listTo = continuous ? bounds.to : start;
    _currentAyah = start;
    _wantPlaying = play;
    _loading = true;
    _completed = false;
    _errorMessage = null;
    _listReady = false;
    _announceAyah(bounds.surah, start);
    _notify();

    // `AudioPlayer.play()` لا يفعل شيئًا إن كانت `playing` أصلًا true، وهذه
    // الراية تبقى مرفوعة بعد اكتمال القائمة السابقة. فلو بنينا قائمة جديدة
    // فوق مشغّل «يظنّ» أنه يعمل، لم يصل أمر تشغيل حقيقي إلى المنصّة وبقيت
    // التلاوة صامتة. الإيقاف المؤقت هنا يخفض الراية فيصير play() فعّالًا.
    try {
      await _player.pause();
    } catch (_) {}
    if (token != _loadToken) return;

    Object? failure;
    var interrupted = false;
    for (var tier = _tier; tier < _sourceTiers; tier++) {
      try {
        await _player.setAudioSources(
          _sourcesFor(bounds.surah, _listFrom, _listTo, tier),
          initialIndex: start - _listFrom,
          initialPosition: initialPosition,
        );
        if (token != _loadToken) return;
        _tier = tier;
        _listReady = true;
        failure = null;
        break;
      } on PlayerInterruptedException catch (e) {
        // إن قاطعنا طلبٌ أحدث فهو المسؤول عن الحالة. أما المقاطعة الداخلية
        // فيجب ألا تترك المشغّل عالقًا في وضع «يحمّل» إلى الأبد.
        if (token != _loadToken) return;
        interrupted = true;
        failure = e;
        break;
      } catch (e) {
        if (token != _loadToken) return;
        failure = e;
      }
    }

    if (token != _loadToken) return;
    _loading = false;

    if (failure != null) {
      if (interrupted) {
        // ليست عطلًا يستحق رسالة خطأ — فقط أعِد الحالة إلى وضع متّسق.
        _wantPlaying = false;
        _notify();
        return;
      }
      _markFailed(failure);
      throw failure;
    }

    // لا ننتظر play(): الـ Future الذي يعيده لا يكتمل إلا بانتهاء التلاوة.
    // ونراجع النية أولًا حتى لا يُبطل هذا التحميل ضغطةَ إيقاف وصلت أثناءه.
    if (_wantPlaying) {
      _playWithoutBlocking();
    }
    _notify();
  }

  /// يبدأ جلسة استماع ضمن [fromAyah]–[toAyah] من [startAyah].
  Future<void> listen({
    required int surah,
    required int fromAyah,
    required int toAyah,
    int? startAyah,
  }) {
    final bounds = ListenBounds(surah: surah, from: fromAyah, to: toAyah);
    final start = bounds.clampAyah(startAyah ?? fromAyah);
    return _serial(() async {
      _bounds = bounds;
      // كل جلسة جديدة تعود للمصدر الأساسي حتى لا يبقى عطلٌ عابر مثبِّتًا للبديل.
      _tier = 0;
      await _load(start, play: true);
    });
  }

  /// ضغط الطالب على آية: إن كانت هي الجارية بدّل تشغيل/إيقاف مؤقت، وإلا
  /// ابدأ منها ضمن النطاق نفسه مع الحفاظ على الوضع المختار (كلي أو آية).
  Future<void> toggleAyah({
    required int surah,
    required int ayah,
    required int fromAyah,
    required int toAyah,
  }) {
    if (hasSession && _bounds?.surah == surah && _currentAyah == ayah) {
      return _wantPlaying ? pause() : resume();
    }
    return listen(
      surah: surah,
      fromAyah: fromAyah,
      toAyah: toAyah,
      startAyah: ayah,
    );
  }

  /// تشغيل البسملة وحدها (وهي الآية 1 من الفاتحة) كجلسة قابلة للإيقاف.
  Future<void> playBasmala() => listen(surah: 1, fromAyah: 1, toAyah: 1);

  Future<void> pause() {
    _wantPlaying = false;
    _notify();
    return _serial(() async {
      if (_disposed) return;
      // إعادة التأكيد داخل الطابور: قد يكون تحميلٌ سابق رفع النية بعد الضغط.
      _wantPlaying = false;
      await _player.pause();
      _notify();
    });
  }

  Future<void> resume() {
    if (!hasSession) return Future<void>.value();
    _wantPlaying = true;
    _completed = false;
    _notify();
    return _serial(() async {
      if (_disposed) return;
      // قد يكون إيقافٌ كامل ألغى الجلسة بينما كان هذا الأمر في الطابور.
      final ayah = _currentAyah;
      if (_bounds == null || ayah == null) return;
      _wantPlaying = true;
      if (_errorMessage != null) {
        _tier = 0;
        await _load(ayah, play: true);
        return;
      }
      if (_player.processingState == ProcessingState.completed || _completed) {
        // انتهت القائمة: أعد تحميلها من الآية الحالية بدل البقاء صامتًا.
        await _load(ayah, play: true);
        return;
      }
      _errorMessage = null;
      _playWithoutBlocking();
      _notify();
    });
  }

  Future<void> restart() {
    final bounds = _bounds;
    if (bounds == null) return Future<void>.value();
    _wantPlaying = true;
    _completed = false;
    _errorMessage = null;
    _tier = 0;
    _notify();
    return _serial(() => _load(bounds.from, play: true));
  }

  Future<void> stop() {
    _wantPlaying = false;
    _loading = false;
    _completed = false;
    _errorMessage = null;
    _listReady = false;
    _loadToken++;
    final hadSession = _bounds != null;
    _bounds = null;
    _currentAyah = null;
    _notify();
    if (!hadSession) return Future<void>.value();
    return _serial(() async {
      if (_disposed) return;
      _wantPlaying = false;
      await _player.stop();
      _notify();
    });
  }

  /// الانتقال للآية التالية أو السابقة داخل النطاق.
  ///
  /// في الوضع الكلي تكون القائمة محمّلة مسبقًا فالانتقال `seek` فوري، ولذلك
  /// لا نُسقط الضغطات المتتابعة: كل ضغطة تُحرّك المؤشّر خطوة إضافية.
  Future<void> playAdjacent({required bool next}) {
    final bounds = _bounds;
    final ayah = _currentAyah;
    if (bounds == null || ayah == null) return Future<void>.value();
    final target = next ? ayah + 1 : ayah - 1;
    if (!bounds.contains(target)) return Future<void>.value();

    _wantPlaying = true;
    _completed = false;
    _errorMessage = null;
    _currentAyah = target;
    _announceAyah(bounds.surah, target);
    _notify();

    return _serial(() async {
      if (_disposed) return;
      final state = _player.processingState;
      final loadedInList =
          _listReady &&
          _mode == ListenMode.continuous &&
          target >= _listFrom &&
          target <= _listTo &&
          state != ProcessingState.idle &&
          state != ProcessingState.loading;
      if (loadedInList) {
        await _player.seek(Duration.zero, index: target - _listFrom);
        if (_wantPlaying) _playWithoutBlocking();
        _notify();
        return;
      }
      await _load(target, play: true);
    });
  }

  Future<void> seek(Duration position) {
    return _serial(() async {
      if (_disposed) return;
      await _player.seek(position);
      _notify();
    });
  }

  /// تغيير الوضع أثناء التشغيل يعيد بناء القائمة من الموضع نفسه، فيسري
  /// الوضع الجديد فورًا بدل انتظار نهاية الجلسة.
  Future<void> setMode(ListenMode value) {
    if (_mode == value) return Future<void>.value();
    _mode = value;
    _notify();
    return _reloadInPlace();
  }

  /// تغيير القارئ يعيد بناء القائمة من الموضع نفسه بصوت القارئ الجديد.
  Future<void> setReciter(QuranReciter value) {
    if (_reciter.id == value.id) return Future<void>.value();
    _reciter = value;
    _tier = 0;
    _notify();
    return _reloadInPlace();
  }

  Future<void> _reloadInPlace() {
    final ayah = _currentAyah;
    if (_bounds == null || ayah == null) return Future<void>.value();
    final at = _player.position;
    final playing = _wantPlaying;
    return _serial(() => _load(ayah, initialPosition: at, play: playing));
  }

  Future<void> dispose() async {
    _disposed = true;
    _wantPlaying = false;
    _loadToken++;
    _onAyahChanged = null;
    _onStateChanged = null;
    await _indexSub?.cancel();
    await _stateSub?.cancel();
    await _errorSub?.cancel();
    // أوقف قبل dispose: على الويب تبقى عناصر Audio المنفصلة عن الـ DOM
    // تُصدر صوتًا إن أُغلقت الجلسة دون stop صريح.
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
