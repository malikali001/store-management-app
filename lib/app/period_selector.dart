import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/period.dart';
import 'providers.dart';
import 'theme.dart';

/// A 3-way segmented control (Month / Quarter / All time) wired to
/// [periodKindProvider]. Used on Home and Reports.
class PeriodSelector extends ConsumerWidget {
  const PeriodSelector({super.key});

  static String label(PeriodKind kind) => switch (kind) {
        PeriodKind.month => 'Month',
        PeriodKind.quarter => 'Quarter',
        PeriodKind.allTime => 'All time',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(periodKindProvider);
    return Wrap(
      spacing: 8,
      children: [
        for (final kind in PeriodKind.values)
          ChoiceChip(
            label: Text(label(kind)),
            selected: selected == kind,
            showCheckmark: false,
            backgroundColor: AppColors.surface,
            selectedColor: AppColors.positive,
            side: const BorderSide(color: AppColors.hairline),
            labelStyle: TextStyle(
              color: selected == kind ? Colors.white : AppColors.ink,
              fontWeight: FontWeight.w500,
            ),
            onSelected: (_) =>
                ref.read(periodKindProvider.notifier).state = kind,
          ),
      ],
    );
  }
}
