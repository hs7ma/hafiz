import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/repositories/demo_repository.dart';
import '../mushaf/mushaf_controller.dart';

class StudentShell extends ConsumerWidget {
  const StudentShell({super.key, required this.child});

  final Widget child;

  int _indexFromLocation(String location) {
    if (location.startsWith('/student/mushaf')) return 1;
    if (location.startsWith('/student/progress')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.toString();
    final index = _indexFromLocation(location);

    return SoftBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) {
            switch (i) {
              case 0:
                context.go('/student');
              case 1:
                context.go('/student/mushaf');
              case 2:
                context.go('/student/progress');
            }
          },
          destinations: const [
            NavigationDestination(
              icon: SvgActionIcon('assets/svg/icon_homework.svg', size: 22),
              label: 'اليوم',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book_rounded),
              label: 'المصحف',
            ),
            NavigationDestination(
              icon: SvgActionIcon('assets/svg/icon_attendance.svg', size: 22),
              label: 'تقدمي',
            ),
          ],
        ),
      ),
    );
  }
}

class StudentHomeScreen extends ConsumerWidget {
  const StudentHomeScreen({super.key});

  void _openMushaf(WidgetRef ref, BuildContext context, {int? surah}) {
    if (surah != null) {
      ref.read(mushafSurahProvider.notifier).open(surah);
    }
    context.go('/student/mushaf');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider);
    final homeworkMap = ref.watch(homeworkControllerProvider);
    final assignment = user == null ? null : homeworkMap[user.id];
    final progress = ref.watch(progressControllerProvider);
    final quran = ref.watch(quranRepositoryProvider);
    final mosque = user == null
        ? null
        : ref.watch(demoRepositoryProvider).mosqueById(user.mosqueId);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('واجهة الطالب'),
        actions: [
          IconButton(
            onPressed: () {
              ref.read(authControllerProvider.notifier).logout();
              context.go('/welcome');
            },
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          FadeSlideIn(
            child: GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'مرحبًا، ${user?.fullName ?? ''}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    mosque?.name ?? '',
                    style: TextStyle(
                      color: AppColors.olive.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          FadeSlideIn(
            delay: const Duration(milliseconds: 100),
            child: Hero(
              tag: 'assignment-card',
              child: Material(
                color: Colors.transparent,
                child: GlassCard(
                  onTap: assignment == null
                      ? null
                      : () => _openMushaf(
                            ref,
                            context,
                            surah: assignment.surahNumber,
                          ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const SvgActionIcon(
                            'assets/svg/icon_homework.svg',
                            size: 32,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'واجب اليوم',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (assignment == null)
                        const Text(
                          'لم يعيّن المدرّس واجبًا لك بعد. يمكنك تصفح المصحف الكامل من التبويب.',
                        )
                      else ...[
                        Text(
                          quran.surahByNumber(assignment.surahNumber).name,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: AppColors.oliveDark,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'من الآية ${assignment.fromAyah} إلى ${assignment.toAyah}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: () => _openMushaf(
                                ref,
                                context,
                                surah: assignment.surahNumber,
                              ),
                              icon: const Icon(Icons.menu_book_rounded),
                              label: const Text('افتح المصحف'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () => _openMushaf(
                                ref,
                                context,
                                surah: assignment.surahNumber,
                              ),
                              icon: const Icon(Icons.headphones_rounded),
                              label: const Text('استماع'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          FadeSlideIn(
            delay: const Duration(milliseconds: 160),
            child: GlassCard(
              onTap: () => context.push('/student/mushaf/index'),
              child: const Row(
                children: [
                  Icon(Icons.list_alt_rounded, color: AppColors.olive),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'فهرس المصحف',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 4),
                        Text('114 سورة — تصفح المصحف الكامل'),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_left),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          FadeSlideIn(
            delay: const Duration(milliseconds: 220),
            child: GlassCard(
              child: Row(
                children: [
                  const SvgActionIcon('assets/svg/icon_audio.svg', size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'آخر موضع وصلت إليه',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          progress == null
                              ? 'اضغط مطولًا على رقم الآية في المصحف لحفظ موضعك'
                              : '${quran.surahByNumber(progress.surahNumber).name} • آية ${progress.ayahNumber}',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(progressControllerProvider);
    final user = ref.watch(authControllerProvider);
    final homeworkMap = ref.watch(homeworkControllerProvider);
    final assignment = user == null ? null : homeworkMap[user.id];
    final quran = ref.watch(quranRepositoryProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('تقدمي'),
        leading: const AppBackButton(fallback: '/student'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SvgActionIcon('assets/svg/icon_attendance.svg', size: 34),
                const SizedBox(height: 12),
                Text(
                  'موضع الحفظ الحالي',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  progress == null
                      ? 'من المصحف: اضغط مطولًا على رقم الآية لحفظ الموضع.'
                      : '${quran.surahByNumber(progress.surahNumber).name} — الآية ${progress.ayahNumber}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SvgActionIcon('assets/svg/icon_homework.svg', size: 34),
                const SizedBox(height: 12),
                Text(
                  'واجب اليوم',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  assignment == null
                      ? 'لا يوجد واجب بعد.'
                      : '${quran.surahByNumber(assignment.surahNumber).name} من ${assignment.fromAyah} إلى ${assignment.toAyah}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
