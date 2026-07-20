import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/quran/quran_audio.dart';
import '../../data/quran/quran_audio_player.dart';
import '../../data/quran/quran_repository.dart';
import '../../data/quran/quran_rules.dart';
import '../../data/quran/surah_info.dart';
import '../../data/repositories/demo_repository.dart';
import 'mushaf_controller.dart';
import 'mushaf_prefs.dart';
import 'tafsir_sheet.dart';

/// شاشة فهرس السور (114) مع تقسيم بصري حسب الأجزاء.
class MushafIndexScreen extends ConsumerStatefulWidget {
  const MushafIndexScreen({super.key});

  @override
  ConsumerState<MushafIndexScreen> createState() => _MushafIndexScreenState();
}

class _MushafIndexScreenState extends ConsumerState<MushafIndexScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final quran = ref.watch(quranRepositoryProvider);
    final current = ref.watch(mushafSurahProvider);
    final filtered = quran.surahs.where((s) {
      if (_query.trim().isEmpty) return true;
      final q = _query.trim();
      return s.name.contains(q) || '${s.number}'.contains(q);
    }).toList();

    final rows = <Widget>[];
    int? lastJuz;
    for (final s in filtered) {
      final juz = juzOfSurah(s.number);
      if (juz != lastJuz) {
        lastJuz = juz;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: Divider(
                    color: AppColors.gold.withValues(alpha: 0.5),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'الجزء ${arabicIndic(juz)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppColors.oliveDark,
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(
                    color: AppColors.gold.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      final selected = s.number == current;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  onTap: () {
                    ref.read(mushafSurahProvider.notifier).open(s.number);
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/student/mushaf');
                    }
                  },
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      selected ? AppColors.olive : AppColors.softGreen,
                  child: Text(
                    '${s.number}',
                    style: TextStyle(
                      color: selected ? Colors.white : AppColors.oliveDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'سورة ${s.name}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color:
                              selected ? AppColors.oliveDark : AppColors.ink,
                        ),
                      ),
                      Text(
                        '${revelationLabelAr(s.number)} • ${s.ayahCount} آية',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_left),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('فهرس المصحف'),
        leading: const AppBackButton(fallback: '/student/mushaf'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'ابحث باسم السورة أو رقمها…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: rows,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'النص العثماني من مشروع تنزيل — ${quran.metadata?.version ?? ''}\n'
              'المرجع: tanzil.net — يُمنع تعديل النص',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.ink.withValues(alpha: 0.55),
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// عرض مصحف متصل (سورة كاملة) وليس بطاقات آيات منفصلة.
class MushafScreen extends ConsumerStatefulWidget {
  const MushafScreen({super.key});

  @override
  ConsumerState<MushafScreen> createState() => _MushafScreenState();
}

class _MushafScreenState extends ConsumerState<MushafScreen> {
  QuranAudioPlayer? _audio;
  int? _playingSurah;
  int? _playingAyah;
  bool _busy = false;
  bool _playing = false;
  bool _paused = false;
  ListenMode _listenMode = ListenMode.continuous;
  String _reciterId = QuranAudioSources.reciters.first.id;

  double _fontSize = MushafPrefs.defaultFontSize;
  MushafTheme _theme = MushafTheme.light;

  final _scrollController = ScrollController();
  final Map<int, GlobalKey> _ayahKeys = {};
  int? _shownSurah;
  Timer? _scrollSaveTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPrefs());
    unawaited(
      ref.read(mushafSurahProvider.notifier).restoreLastOpened(),
    );
  }

  Future<void> _loadPrefs() async {
    final font = await MushafPrefs.fontSize();
    final theme = await MushafPrefs.theme();
    final reciter = await MushafPrefs.reciterId();
    if (!mounted) return;
    setState(() {
      _fontSize = font;
      _theme = theme;
      if (reciter != null &&
          QuranAudioSources.reciters.any((r) => r.id == reciter)) {
        _reciterId = reciter;
      }
    });
  }

  @override
  void dispose() {
    _scrollSaveTimer?.cancel();
    _scrollController.dispose();
    unawaited(_audio?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  void _syncPlaybackFlags(QuranAudioPlayer audio) {
    _playing = audio.isPlaying;
    _paused = audio.isPaused;
    _playingSurah = audio.currentSurah;
    _playingAyah = audio.currentAyah;
    _listenMode = audio.mode;
  }

  QuranAudioPlayer _ensureAudio(QuranRepository quran) {
    final existing = _audio;
    if (existing != null) return existing;
    final player = QuranAudioPlayer(quran);
    player.reciter = QuranAudioSources.byId(_reciterId);
    player.mode = _listenMode;
    player.ensureListeners(
      onAyahChanged: (surah, ayah) {
        if (!mounted) return;
        setState(() {
          _playingAyah = ayah;
          _syncPlaybackFlags(player);
        });
        _scrollToAyah(ayah);
      },
      onStateChanged: () {
        if (!mounted) return;
        setState(() => _syncPlaybackFlags(player));
      },
    );
    _audio = player;
    return player;
  }

  Future<void> _runAudio(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      final audio = _audio;
      if (mounted && audio != null) {
        setState(() => _syncPlaybackFlags(audio));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذّر تشغيل التلاوة. تحقق من الإنترنت.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleAudio(int surah, int ayah, QuranRepository quran) async {
    await _runAudio(() async {
      final audio = _ensureAudio(quran);
      audio.mode = ListenMode.singleAyah;
      await audio.toggleAyah(surah, ayah);
    });
  }

  Future<void> _startHomeworkListen(
    int surah,
    int from,
    int to,
    QuranRepository quran, {
    int? startAyah,
  }) async {
    await _runAudio(() async {
      final audio = _ensureAudio(quran);
      audio.mode = _listenMode;
      await audio.playHomework(
        surah: surah,
        fromAyah: from,
        toAyah: to,
        startAyah: startAyah ?? _playingAyah,
      );
    });
    if (_playingAyah != null) _scrollToAyah(_playingAyah!);
  }

  Future<void> _pauseAudio() async {
    final audio = _audio;
    if (audio == null) return;
    await audio.pause();
    if (mounted) setState(() => _syncPlaybackFlags(audio));
  }

  Future<void> _resumeAudio() async {
    await _runAudio(() async {
      final audio = _audio;
      if (audio == null) return;
      await audio.resume();
    });
  }

  Future<void> _stopAudio() async {
    final audio = _audio;
    if (audio == null) return;
    await audio.stop();
    if (mounted) {
      setState(() {
        _syncPlaybackFlags(audio);
        _playingAyah = null;
        _playingSurah = null;
      });
    }
  }

  Future<void> _playAdjacent(QuranRepository quran, {required bool next}) async {
    await _runAudio(() async {
      final audio = _ensureAudio(quran);
      await audio.playAdjacent(next: next);
    });
  }

  void _setListenMode(ListenMode mode, QuranRepository quran) {
    setState(() => _listenMode = mode);
    _ensureAudio(quran).mode = mode;
  }

  void _scrollToAyah(int ayah) {
    final ctx = _ayahKeys[ayah]?.currentContext;
    if (ctx == null) return;
    unawaited(
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.25,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _onSurahChanged(int surahNumber) {
    if (_shownSurah == surahNumber) return;
    _shownSurah = surahNumber;
    _ayahKeys.clear();
    // استرجاع آخر موضع قراءة للسورة بعد بناء المحتوى.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _shownSurah != surahNumber) return;
      final saved = await MushafPrefs.scrollOffset(surahNumber);
      if (!mounted ||
          _shownSurah != surahNumber ||
          saved == null ||
          !_scrollController.hasClients) {
        return;
      }
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(saved.clamp(0.0, max));
    });
  }

  void _scheduleScrollSave() {
    final surah = _shownSurah;
    if (surah == null || !_scrollController.hasClients) return;
    _scrollSaveTimer?.cancel();
    final offset = _scrollController.offset;
    _scrollSaveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(MushafPrefs.saveScrollOffset(surah, offset));
    });
  }

  Future<void> _showJumpToAyahDialog(int surahNumber, int ayahCount) async {
    final ctrl = TextEditingController();
    final target = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('الانتقال إلى آية'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'رقم الآية (1–$ayahCount)',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
            child: const Text('انتقال'),
          ),
        ],
      ),
    );
    if (target == null || target < 1 || target > ayahCount) return;
    _scrollToAyah(target);
  }

  Future<void> _showReadingSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.ivory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'إعدادات القراءة',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text(
                        'حجم الخط',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Text(
                        _fontSize.round().toString(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.oliveDark,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _fontSize,
                    min: MushafPrefs.minFontSize,
                    max: MushafPrefs.maxFontSize,
                    divisions:
                        (MushafPrefs.maxFontSize - MushafPrefs.minFontSize)
                            .round(),
                    label: '${_fontSize.round()}',
                    onChanged: (v) {
                      setSheet(() {});
                      setState(() => _fontSize = v);
                    },
                    onChangeEnd: (v) =>
                        unawaited(MushafPrefs.saveFontSize(v)),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'وضع القراءة',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<MushafTheme>(
                    segments: MushafTheme.values
                        .map(
                          (t) => ButtonSegment(
                            value: t,
                            label: Text(t.labelAr),
                            icon: Icon(t.icon, size: 18),
                          ),
                        )
                        .toList(),
                    selected: {_theme},
                    onSelectionChanged: (set) {
                      if (set.isEmpty) return;
                      setSheet(() {});
                      setState(() => _theme = set.first);
                      unawaited(MushafPrefs.saveTheme(set.first));
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  TextStyle _quranStyle(MushafPalette palette) => GoogleFonts.amiriQuran(
        fontSize: _fontSize,
        height: 2.15,
        color: palette.text,
      );

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider);
    final homeworkMap = ref.watch(homeworkControllerProvider);
    final assignment = user == null ? null : homeworkMap[user.id];
    final progress = ref.watch(progressControllerProvider);
    final quran = ref.watch(quranRepositoryProvider);
    final surahNumber = ref.watch(mushafSurahProvider);

    _onSurahChanged(surahNumber);

    final ayahs = quran.ayahsOf(surahNumber);
    final surah = quran.surahByNumber(surahNumber);
    final bismillah = quran.bismillahOf(surahNumber);
    final homeworkHere = assignment?.surahNumber == surahNumber;
    final from = homeworkHere ? assignment!.fromAyah : null;
    final to = homeworkHere ? assignment!.toAyah : null;
    final palette = MushafPalette.of(_theme);
    final playingHere = _playingSurah == null || _playingSurah == surahNumber;

    for (var i = 1; i <= ayahs.length; i++) {
      _ayahKeys.putIfAbsent(i, GlobalKey.new);
    }

    final hasAudioSession = _playing || _paused;
    // لا نكرر أزرار التشغيل: لوحة الواجب أعلى الصفحة تكفي عند وجود واجب هنا.
    final showMiniPlayer = hasAudioSession && !(homeworkHere && from != null && to != null);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('المصحف • ${surah.name}'),
        leading: const AppBackButton(fallback: '/student'),
        actions: [
          IconButton(
            tooltip: 'الفهرس',
            onPressed: () => context.push('/student/mushaf/index'),
            icon: const Icon(Icons.list_alt_rounded),
          ),
          IconButton(
            tooltip: 'إعدادات القراءة',
            onPressed: _showReadingSettings,
            icon: const Icon(Icons.tune_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'اختيار القارئ',
            onSelected: (id) {
              setState(() {
                _reciterId = id;
                _ensureAudio(quran).reciter = QuranAudioSources.byId(id);
              });
              unawaited(MushafPrefs.saveReciterId(id));
            },
            itemBuilder: (context) => QuranAudioSources.reciters
                .map(
                  (r) => PopupMenuItem(
                    value: r.id,
                    child: Text(
                      r.nameAr,
                      style: TextStyle(
                        fontWeight: r.id == _reciterId
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                )
                .toList(),
            icon: const Icon(Icons.record_voice_over_rounded),
          ),
        ],
      ),
      bottomNavigationBar: showMiniPlayer
          ? _MiniPlayerBar(
              surahName: _playingSurah != null
                  ? quran.surahByNumber(_playingSurah!).name
                  : surah.name,
              ayah: _playingAyah,
              playing: _playing,
              busy: _busy,
              onPlayPause: _playing ? _pauseAudio : _resumeAudio,
              onStop: _stopAudio,
              onPrev: () => _playAdjacent(quran, next: false),
              onNext: () => _playAdjacent(quran, next: true),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                IconButton.filledTonal(
                  onPressed: surahNumber <= 1
                      ? null
                      : () => ref
                          .read(mushafSurahProvider.notifier)
                          .open(surahNumber - 1),
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'السورة السابقة',
                ),
                Expanded(
                  child: Text(
                    'سورة ${surah.name}  •  ${surah.ayahCount} آية',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'الانتقال إلى آية',
                  onPressed: () =>
                      _showJumpToAyahDialog(surahNumber, surah.ayahCount),
                  icon: const Icon(Icons.pin_outlined),
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  onPressed: surahNumber >= 114
                      ? null
                      : () => ref
                          .read(mushafSurahProvider.notifier)
                          .open(surahNumber + 1),
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'السورة التالية',
                ),
              ],
            ),
          ),
          if (homeworkHere && from != null && to != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _HomeworkListenPanel(
                fromAyah: from,
                toAyah: to,
                currentAyah: playingHere ? _playingAyah : null,
                listenMode: _listenMode,
                busy: _busy,
                playing: _playing && playingHere,
                paused: _paused && playingHere,
                onModeChanged: (mode) => _setListenMode(mode, quran),
                onPlay: () => _startHomeworkListen(
                  surahNumber,
                  from,
                  to,
                  quran,
                ),
                onPause: _pauseAudio,
                onResume: _resumeAudio,
                onStop: _stopAudio,
                onPrev: () => _playAdjacent(quran, next: false),
                onNext: () => _playAdjacent(quran, next: true),
              ),
            ),
          Expanded(
            child: GestureDetector(
              onHorizontalDragEnd: (details) {
                final v = details.primaryVelocity ?? 0;
                if (v > 320 && surahNumber > 1) {
                  ref
                      .read(mushafSurahProvider.notifier)
                      .open(surahNumber - 1);
                } else if (v < -320 && surahNumber < 114) {
                  ref
                      .read(mushafSurahProvider.notifier)
                      .open(surahNumber + 1);
                }
              },
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                decoration: BoxDecoration(
                  color: palette.background,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: palette.border),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.olive.withValues(alpha: 0.06),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ayahs.isEmpty
                    ? const Center(child: Text('تعذّر تحميل نص السورة.'))
                    : NotificationListener<ScrollEndNotification>(
                        onNotification: (_) {
                          _scheduleScrollSave();
                          return false;
                        },
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(18, 22, 18, 28),
                          child: Column(
                            children: [
                              _SurahHeaderFrame(
                                surahName: surah.name,
                                subtitle:
                                    '${revelationLabelAr(surahNumber)} • '
                                    '${arabicIndic(surah.ayahCount)} آية • '
                                    'الجزء ${arabicIndic(juzOfSurah(surahNumber))}',
                                palette: palette,
                              ),
                              if (bismillah != null) ...[
                                const SizedBox(height: 16),
                                Text(
                                  bismillah,
                                  textAlign: TextAlign.center,
                                  style: _quranStyle(palette).copyWith(
                                    fontSize: (_fontSize - 2).clamp(20, 38),
                                    color: palette.accent,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'بسملة افتتاح — للعرض فقط وليست آية معدودة',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: palette.subtle),
                                ),
                                TextButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _runAudio(() async {
                                            await _ensureAudio(quran)
                                                .playOpeningBasmala();
                                          }),
                                  icon: const Icon(Icons.volume_up_outlined),
                                  label: const Text('تشغيل البسملة وحدها'),
                                ),
                              ],
                              if (QuranRules.isFatiha(surahNumber))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    'في رواية حفص: البسملة هي الآية 1 من الفاتحة',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: palette.subtle),
                                  ),
                                ),
                              const SizedBox(height: 18),
                              Text(
                                'اضغط الآية للاستماع • اضغط مطوّلًا: تعليم الحفظ أو التفسير',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: palette.subtle),
                              ),
                              const SizedBox(height: 10),
                              _ContinuousSurahText(
                                ayahs: ayahs,
                                style: _quranStyle(palette),
                                palette: palette,
                                ayahKeys: _ayahKeys,
                                playingAyah:
                                    playingHere ? _playingAyah : null,
                                highlightFrom: from,
                                highlightTo: to,
                                progressAyah:
                                    progress?.surahNumber == surahNumber
                                        ? progress?.ayahNumber
                                        : null,
                                onAyahTap: (ayah) =>
                                    _toggleAudio(surahNumber, ayah, quran),
                                onAyahLongPress: (ayah) {
                                  showAyahActionsSheet(
                                    context,
                                    surahName: surah.name,
                                    ayahNumber: ayah,
                                    palette: palette,
                                    onMarkProgress: () {
                                      ref
                                          .read(
                                            progressControllerProvider
                                                .notifier,
                                          )
                                          .save(surahNumber, ayah);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'تم تعليم مكان الحفظ عند الآية $ayah',
                                          ),
                                        ),
                                      );
                                    },
                                    onShowTafsir: () {
                                      final text = quran.ayahText(
                                        surahNumber,
                                        ayah,
                                      );
                                      if (text == null) return;
                                      final tafsir = ref
                                          .read(tafsirMuyassarProvider)
                                          .of(surahNumber, ayah);
                                      final meta = ref
                                          .read(tafsirMuyassarProvider)
                                          .metadata;
                                      showTafsirSheet(
                                        context,
                                        surahName: surah.name,
                                        surahNumber: surahNumber,
                                        ayahNumber: ayah,
                                        ayahText: text,
                                        tafsirText: tafsir,
                                        sourceLabel: meta?.source ??
                                            'التفسير الميسر — مجمع الملك فهد',
                                        palette: palette,
                                        onListen: () => _toggleAudio(
                                          surahNumber,
                                          ayah,
                                          quran,
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                              const SizedBox(height: 28),
                              Text(
                                'المصدر: مشروع تنزيل (Tanzil) — نص عثماني دون تعديل\n'
                                '${quran.metadata?.website ?? 'https://tanzil.net'}',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: palette.subtle,
                                      height: 1.4,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// إطار زخرفي لعنوان السورة أشبه بالمصاحف المطبوعة.
class _SurahHeaderFrame extends StatelessWidget {
  const _SurahHeaderFrame({
    required this.surahName,
    required this.subtitle,
    required this.palette,
  });

  final String surahName;
  final String subtitle;
  final MushafPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold, width: 1.6),
        color: palette.markerFill,
      ),
      padding: const EdgeInsets.all(4),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.gold.withValues(alpha: 0.55),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.star_rounded,
                  size: 14,
                  color: AppColors.gold.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 10),
                Text(
                  'سورة $surahName',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: palette.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.star_rounded,
                  size: 14,
                  color: AppColors.gold.withValues(alpha: 0.9),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: palette.subtle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// شريط تشغيل مصغّر يظهر أسفل الشاشة أثناء الاستماع.
class _MiniPlayerBar extends StatelessWidget {
  const _MiniPlayerBar({
    required this.surahName,
    required this.ayah,
    required this.playing,
    required this.busy,
    required this.onPlayPause,
    required this.onStop,
    required this.onPrev,
    required this.onNext,
  });

  final String surahName;
  final int? ayah;
  final bool playing;
  final bool busy;
  final VoidCallback onPlayPause;
  final VoidCallback onStop;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.oliveDark,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.oliveDark.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'سورة $surahName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  if (ayah != null)
                    Text(
                      'الآية ${arabicIndic(ayah!)}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'الآية السابقة',
              onPressed: busy ? null : onPrev,
              icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                ),
              )
            else
              IconButton(
                tooltip: playing ? 'إيقاف مؤقت' : 'متابعة',
                onPressed: onPlayPause,
                icon: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            IconButton(
              tooltip: 'الآية التالية',
              onPressed: busy ? null : onNext,
              icon: const Icon(
                Icons.skip_previous_rounded,
                color: Colors.white,
              ),
            ),
            IconButton(
              tooltip: 'إيقاف',
              onPressed: busy ? null : onStop,
              icon: const Icon(Icons.stop_rounded, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeworkListenPanel extends StatelessWidget {
  const _HomeworkListenPanel({
    required this.fromAyah,
    required this.toAyah,
    required this.currentAyah,
    required this.listenMode,
    required this.busy,
    required this.playing,
    required this.paused,
    required this.onModeChanged,
    required this.onPlay,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onPrev,
    required this.onNext,
  });

  final int fromAyah;
  final int toAyah;
  final int? currentAyah;
  final ListenMode listenMode;
  final bool busy;
  final bool playing;
  final bool paused;
  final ValueChanged<ListenMode> onModeChanged;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  bool get _inRange =>
      currentAyah != null &&
      currentAyah! >= fromAyah &&
      currentAyah! <= toAyah;

  bool get _canPrev => _inRange && currentAyah! > fromAyah && !busy;

  bool get _canNext => _inRange && currentAyah! < toAyah && !busy;

  @override
  Widget build(BuildContext context) {
    final status = playing
        ? 'جاري الاستماع • الآية $currentAyah'
        : paused && _inRange
            ? 'متوقف مؤقتًا • الآية $currentAyah'
            : 'واجب اليوم: الآيات $fromAyah–$toAyah';

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SvgActionIcon('assets/svg/icon_audio.svg', size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  status,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<ListenMode>(
            segments: const [
              ButtonSegment(
                value: ListenMode.singleAyah,
                label: Text('آية'),
                icon: Icon(Icons.looks_one_outlined, size: 18),
              ),
              ButtonSegment(
                value: ListenMode.continuous,
                label: Text('كلي'),
                icon: Icon(Icons.playlist_play_rounded, size: 18),
              ),
            ],
            selected: {listenMode},
            onSelectionChanged: busy
                ? null
                : (set) {
                    if (set.isEmpty) return;
                    onModeChanged(set.first);
                  },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(
                Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'الآية السابقة',
                onPressed: _canPrev ? onPrev : null,
                icon: const Icon(Icons.skip_next_rounded),
              ),
              const SizedBox(width: 4),
              if (playing)
                IconButton.filled(
                  tooltip: 'إيقاف مؤقت',
                  onPressed: busy ? null : onPause,
                  icon: const Icon(Icons.pause_rounded),
                )
              else if (paused && _inRange)
                IconButton.filled(
                  tooltip: 'متابعة',
                  onPressed: busy ? null : onResume,
                  icon: const Icon(Icons.play_arrow_rounded),
                )
              else
                IconButton.filled(
                  tooltip: 'استماع',
                  onPressed: busy ? null : onPlay,
                  icon: const Icon(Icons.play_arrow_rounded),
                ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: 'إيقاف',
                onPressed: (!playing && !paused) || busy ? null : onStop,
                icon: const Icon(Icons.stop_rounded),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: 'الآية التالية',
                onPressed: _canNext ? onNext : null,
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              const Spacer(),
              if (busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              else
                Text(
                  listenMode == ListenMode.continuous ? 'متواصل' : 'آية واحدة',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.olive.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w700,
                      ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContinuousSurahText extends StatelessWidget {
  const _ContinuousSurahText({
    required this.ayahs,
    required this.style,
    required this.palette,
    required this.ayahKeys,
    required this.onAyahTap,
    required this.onAyahLongPress,
    this.playingAyah,
    this.highlightFrom,
    this.highlightTo,
    this.progressAyah,
  });

  final List<String> ayahs;
  final TextStyle style;
  final MushafPalette palette;
  final Map<int, GlobalKey> ayahKeys;
  final int? playingAyah;
  final int? highlightFrom;
  final int? highlightTo;
  final int? progressAyah;
  final void Function(int ayah) onAyahTap;
  final void Function(int ayah) onAyahLongPress;

  @override
  Widget build(BuildContext context) {
    // Wrap بدل Text.rich+WidgetSpan لتفادي اختلال ترتيب RTL على الويب.
    return Align(
      alignment: Alignment.topRight,
      child: Wrap(
        alignment: WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 10,
        textDirection: TextDirection.rtl,
        children: [
          for (var i = 0; i < ayahs.length; i++)
            _AyahChip(
              key: ayahKeys[i + 1],
              number: i + 1,
              text: ayahs[i],
              style: style,
              palette: palette,
              playing: playingAyah == i + 1,
              inHomework: highlightFrom != null &&
                  highlightTo != null &&
                  (i + 1) >= highlightFrom! &&
                  (i + 1) <= highlightTo!,
              isProgress: progressAyah == i + 1,
              onTap: () => onAyahTap(i + 1),
              onLongPress: () => onAyahLongPress(i + 1),
            ),
        ],
      ),
    );
  }
}

class _AyahChip extends StatelessWidget {
  const _AyahChip({
    super.key,
    required this.number,
    required this.text,
    required this.style,
    required this.palette,
    required this.playing,
    required this.inHomework,
    required this.isProgress,
    required this.onTap,
    required this.onLongPress,
  });

  final int number;
  final String text;
  final TextStyle style;
  final MushafPalette palette;
  final bool playing;
  final bool inHomework;
  final bool isProgress;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final markerSize = (style.fontSize ?? 28) + 2;
    return Material(
      color: playing
          ? palette.playingBg
          : inHomework
              ? palette.homeworkBg
              : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: RichText(
            textDirection: TextDirection.rtl,
            text: TextSpan(
              children: [
                TextSpan(
                  text: text,
                  style: style.copyWith(
                    decoration: isProgress ? TextDecoration.underline : null,
                    decorationColor: palette.accent,
                  ),
                ),
                const TextSpan(text: ' '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Container(
                    width: markerSize,
                    height: markerSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: playing ? AppColors.gold : palette.markerFill,
                      border: Border.all(
                        color: playing
                            ? AppColors.gold
                            : AppColors.gold.withValues(alpha: 0.8),
                        width: 1.4,
                      ),
                    ),
                    child: Text(
                      arabicIndic(number),
                      style: TextStyle(
                        color: playing ? Colors.white : palette.accent,
                        fontSize: (style.fontSize ?? 28) * 0.42,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
