import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_widgets.dart';

/// بطاقة عدّاد مختصرة للوحات الإدارية — بدون مصطلحات تقنية.
class DashboardStatTile extends StatelessWidget {
  const DashboardStatTile({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.padding = const EdgeInsets.all(16),
  });

  final String label;
  final String value;
  final String? hint;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.oliveDark,
                ),
          ),
          if (hint != null && hint!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              hint!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.ink.withValues(alpha: 0.55),
                    height: 1.35,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

/// تنبيه قصير عندما تحتاج لوحة التحكم إلى انتباه المستخدم.
class DashboardAttentionBanner extends StatelessWidget {
  const DashboardAttentionBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.softGreen.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.olive.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.oliveDark, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppColors.ink.withValues(alpha: 0.85),
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String arabicCount(int n, {required String one, required String two, required String many}) {
  if (n == 0) return many;
  if (n == 1) return one;
  if (n == 2) return two;
  return '$n $many';
}
