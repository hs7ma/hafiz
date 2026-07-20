import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../data/quran/surah_info.dart';
import 'mushaf_prefs.dart';

/// قائمة خيارات الآية: تعليم موضع الحفظ أو عرض التفسير.
Future<void> showAyahActionsSheet(
  BuildContext context, {
  required String surahName,
  required int ayahNumber,
  required MushafPalette palette,
  required VoidCallback onMarkProgress,
  required VoidCallback onShowTafsir,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Container(
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: palette.border),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.subtle.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'سورة $surahName • الآية ${arabicIndic(ayahNumber)}',
                textAlign: TextAlign.center,
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: palette.accent,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'ماذا تريد أن تفعل؟',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: palette.subtle,
                ),
              ),
              const SizedBox(height: 16),
              _AyahActionTile(
                icon: Icons.bookmark_added_outlined,
                title: 'تعليمليم مكان الحفظ',
                subtitle: 'حفظ موضعك عند هذه الآية',
                palette: palette,
                onTap: () {
                  Navigator.pop(ctx);
                  onMarkProgress();
                },
              ),
              const SizedBox(height: 10),
              _AyahActionTile(
                icon: Icons.menu_book_rounded,
                title: 'عرض تفسير الآية',
                subtitle: 'التفسير الميسر لهذه الآية',
                palette: palette,
                emphasize: true,
                onTap: () {
                  Navigator.pop(ctx);
                  onShowTafsir();
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _AyahActionTile extends StatelessWidget {
  const _AyahActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.palette,
    required this.onTap,
    this.emphasize = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final MushafPalette palette;
  final VoidCallback onTap;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: emphasize
          ? AppColors.gold.withValues(alpha: 0.14)
          : palette.markerFill,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: emphasize
                  ? AppColors.gold.withValues(alpha: 0.55)
                  : palette.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: emphasize
                      ? AppColors.gold.withValues(alpha: 0.22)
                      : palette.background,
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.5),
                  ),
                ),
                child: Icon(icon, color: palette.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: palette.subtle,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_left, color: palette.subtle),
            ],
          ),
        ),
      ),
    );
  }
}

/// ورقة تفسير ميسّر لآية واحدة — تصميم دافئ متناسق مع صفحة المصحف.
Future<void> showTafsirSheet(
  BuildContext context, {
  required String surahName,
  required int surahNumber,
  required int ayahNumber,
  required String ayahText,
  required String? tafsirText,
  required String sourceLabel,
  required MushafPalette palette,
  VoidCallback? onListen,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final height = MediaQuery.sizeOf(ctx).height * 0.78;
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.oliveDark.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: palette.subtle.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'التفسير الميسر',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: palette.accent,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'سورة $surahName • الآية ${arabicIndic(ayahNumber)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: palette.subtle,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.pop(ctx),
                    icon: Icon(Icons.close_rounded, color: palette.accent),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  'مجمع الملك فهد لطباعة المصحف الشريف',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: palette.accent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                      decoration: BoxDecoration(
                        color: palette.markerFill,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: palette.border),
                      ),
                      child: Column(
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.gold,
                                  width: 1.4,
                                ),
                                color: palette.background,
                              ),
                              child: Text(
                                arabicIndic(ayahNumber),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: palette.accent,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            ayahText,
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.rtl,
                            style: GoogleFonts.amiriQuran(
                              fontSize: 24,
                              height: 2.0,
                              color: palette.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: AppColors.gold.withValues(alpha: 0.45),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            'معنى الآية',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: palette.accent,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: AppColors.gold.withValues(alpha: 0.45),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (tafsirText == null || tafsirText.trim().isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'تعذّر العثور على تفسير لهذه الآية في الملف المحلي.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: palette.subtle),
                        ),
                      )
                    else
                      Text(
                        tafsirText,
                        textAlign: TextAlign.justify,
                        textDirection: TextDirection.rtl,
                        style: GoogleFonts.ibmPlexSansArabic(
                          fontSize: 16.5,
                          height: 1.85,
                          color: palette.text,
                        ),
                      ),
                    const SizedBox(height: 20),
                    Text(
                      sourceLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: palette.subtle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (onListen != null)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        onListen();
                      },
                      icon: const Icon(Icons.volume_up_outlined),
                      label: const Text('استماع للآية'),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
