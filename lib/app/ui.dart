import 'package:flutter/material.dart';

import 'theme.dart';

/// Human-readable app version. Keep in sync with `version:` in pubspec.yaml.
const appVersion = '1.1.0 (2)';

/// Opens a form/detail as a scrollable bottom sheet (Section 7).
Future<T?> showAppSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: child,
        ),
      ),
    ),
  );
}

/// Standard header row for a bottom sheet: a grab handle + title.
class SheetHeader extends StatelessWidget {
  final String title;
  const SheetHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.hairline,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// A white rounded card with a hairline border (Section 15).
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      padding: padding,
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: card,
    );
  }
}

/// A dashboard metric tile: label + big value, value coloured by sign option.
class MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const MetricCard(
      {super.key, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 8),
          // Shrink-to-fit so long amounts never clip on narrow screens.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: tabularFigures.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lays [cards] into evenly-sized columns that adapt to the available width:
/// [wideColumns] at/above [breakpoint], otherwise [narrowColumns].
///
/// Cards are **content-sized** (no fixed aspect ratio), so they never clip when
/// amounts are long or the OS text scale is large; each row is height-matched
/// via [IntrinsicHeight]. This is the responsive replacement for a GridView
/// with a fixed childAspectRatio.
class ResponsiveCardGrid extends StatelessWidget {
  final List<Widget> cards;
  final int narrowColumns;
  final int wideColumns;
  final double breakpoint;
  final double gap;
  const ResponsiveCardGrid({
    super.key,
    required this.cards,
    this.narrowColumns = 2,
    this.wideColumns = 4,
    this.breakpoint = 560,
    this.gap = 12,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols =
            constraints.maxWidth >= breakpoint ? wideColumns : narrowColumns;
        final rows = <Widget>[];
        for (var i = 0; i < cards.length; i += cols) {
          final rowChildren = <Widget>[];
          for (var col = 0; col < cols; col++) {
            if (col > 0) rowChildren.add(SizedBox(width: gap));
            final idx = i + col;
            rowChildren.add(Expanded(
              child: idx < cards.length ? cards[idx] : const SizedBox(),
            ));
          }
          if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
          rows.add(IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rowChildren,
            ),
          ));
        }
        return Column(children: rows);
      },
    );
  }
}

/// A section label above a group of cards.
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Empty-state placeholder.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const EmptyState({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

/// A small pill chip used on Home.
class InfoChip extends StatelessWidget {
  final String text;
  final Color color;
  final VoidCallback? onTap;
  const InfoChip(
      {super.key, required this.text, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Text(text,
            style: TextStyle(color: color, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

void showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: AppColors.danger,
  ));
}

void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Confirm dialog returning true if the user confirms.
Future<bool> confirm(BuildContext context,
    {required String title,
    required String message,
    String confirmLabel = 'Confirm',
    bool danger = false}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return res ?? false;
}
