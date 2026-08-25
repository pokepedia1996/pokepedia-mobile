import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

/// One trail entry — [href] null (or the last item) renders as plain text.
typedef BreadcrumbItem = ({String label, String? href});

/// Ports `components/ui/breadcrumb.tsx` — caption-sized trail with chevron
/// separators, scrolling sideways rather than wrapping.
class AppBreadcrumb extends StatelessWidget {
  const AppBreadcrumb({super.key, required this.items});

  final List<BreadcrumbItem> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.chevron_right,
                  size: 14,
                  color: context.mutedForeground,
                ),
              ),
            if (items[i].href == null || i == items.length - 1)
              Text(
                items[i].label,
                style: AppTypography.captionSemibold(colors.onSurface),
              )
            else
              InkWell(
                onTap: () => context.push(items[i].href!),
                child: Text(
                  items[i].label,
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
