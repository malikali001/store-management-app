import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../data/repository.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import '../security/lock_settings.dart';
import '../services/backup.dart';
import '../services/backup_status.dart';

/// Section 7.12 — settings. Pushed via MaterialPageRoute from the Home gear.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _storeName;
  late final TextEditingController _currency;
  late final TextEditingController _decimalPlaces;
  late final TextEditingController _openingCash;
  late final TextEditingController _lowStock;
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _storeName = TextEditingController();
    _currency = TextEditingController();
    _decimalPlaces = TextEditingController();
    _openingCash = TextEditingController();
    _lowStock = TextEditingController();
  }

  void _hydrate(StoreSettings s) {
    if (_initialised) return;
    _storeName.text = s.storeName;
    _currency.text = s.currency;
    _decimalPlaces.text = '${s.decimalPlaces}';
    _openingCash.text = '${s.openingCash}';
    _lowStock.text = '${s.lowStock}';
    _initialised = true;
  }

  @override
  void dispose() {
    _storeName.dispose();
    _currency.dispose();
    _decimalPlaces.dispose();
    _openingCash.dispose();
    _lowStock.dispose();
    super.dispose();
  }

  StoreRepository get _repo => ref.read(repositoryProvider);

  Future<void> _save(String key, String value) async {
    await _repo.setSetting(key, value);
    if (!mounted) return;
    showToast(context, 'Saved');
  }

  @override
  Widget build(BuildContext context) {
    final ledgerAsync = ref.watch(ledgerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Settings')),
      body: ledgerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (ledger) {
          _hydrate(ledger.settings);
          return _buildBody(context, ledger);
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, Ledger ledger) {
    final hasData = ledger.products.isNotEmpty ||
        ledger.salespersons.isNotEmpty ||
        ledger.txns.isNotEmpty ||
        ledger.shops.isNotEmpty ||
        ledger.shopPurchases.isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Store'),
          AppCard(
            child: Column(
              children: [
                _field('Store name', _storeName,
                    onSave: () => _save('store_name', _storeName.text.trim())),
                const SizedBox(height: 12),
                _field('Currency symbol', _currency,
                    onSave: () => _save('currency', _currency.text.trim())),
                const SizedBox(height: 12),
                _field('Decimal places', _decimalPlaces,
                    keyboard: TextInputType.number,
                    digitsOnly: true,
                    onSave: () => _save('decimal_places',
                        '${int.tryParse(_decimalPlaces.text.trim()) ?? 0}')),
                const SizedBox(height: 12),
                _field('Opening cash (minor units)', _openingCash,
                    keyboard: TextInputType.number,
                    digitsOnly: true,
                    onSave: () => _save('opening_cash',
                        '${int.tryParse(_openingCash.text.trim()) ?? 0}')),
                const SizedBox(height: 12),
                _field('Low-stock threshold', _lowStock,
                    keyboard: TextInputType.number,
                    digitsOnly: true,
                    onSave: () => _save('low_stock',
                        '${int.tryParse(_lowStock.text.trim()) ?? 20}')),
              ],
            ),
          ),
          const SectionTitle('Manage lists'),
          const _ListManager(kind: 'category', title: 'Categories'),
          const SizedBox(height: 12),
          const _ListManager(kind: 'brand', title: 'Brands'),
          const SizedBox(height: 12),
          const _ListManager(
              kind: 'expense_category', title: 'Expense categories'),
          const SectionTitle('Security'),
          const LockSettingsSection(),
          const SectionTitle('Data'),
          Consumer(builder: (context, ref, _) {
            final status = ref.watch(backupStatusProvider).valueOrNull;
            if (status == null) return const SizedBox.shrink();
            final stale = status.isStale;
            return Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Row(
                children: [
                  Icon(stale ? Icons.warning_amber_rounded : Icons.cloud_done_outlined,
                      size: 16,
                      color: stale ? AppColors.warning : AppColors.muted),
                  const SizedBox(width: 6),
                  Text(status.humanLabel,
                      style: TextStyle(
                          color: stale ? AppColors.warning : AppColors.muted,
                          fontSize: 13)),
                ],
              ),
            );
          }),
          AppCard(
            child: Column(
              children: [
                _actionRow(
                  icon: Icons.backup_outlined,
                  label: 'Back up everything',
                  onTap: () => backupToFile(context, ref),
                ),
                const Divider(height: 16),
                _actionRow(
                  icon: Icons.restore_outlined,
                  label: 'Restore from backup',
                  onTap: _restore,
                ),
                // Demo data only makes sense on a fresh, empty store — once
                // there is real data it could only destroy it, so it is hidden.
                if (!hasData) ...[
                  const Divider(height: 16),
                  _actionRow(
                    icon: Icons.auto_awesome_outlined,
                    label: 'Load demo data',
                    onTap: _loadDemo,
                  ),
                ],
                // Clearing everything is only offered when there is something
                // to clear, and is guarded by a type-to-confirm step.
                if (hasData) ...[
                  const Divider(height: 16),
                  _actionRow(
                    icon: Icons.delete_outline,
                    label: 'Clear all data',
                    danger: true,
                    onTap: () => _clearAll(ledger.settings.storeName),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('Store Manager · v$appVersion',
                style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Future<void> _restore() async {
    await restoreFromFile(context, ref);
    if (!mounted) return;
    // The restored settings differ from what the fields currently show; force a
    // re-hydrate so a later field save cannot write stale values over the
    // restored data.
    setState(() => _initialised = false);
  }

  Future<void> _loadDemo() async {
    final ok = await confirm(
      context,
      title: 'Load demo data',
      message:
          'This replaces all current data with a realistic sample shop. Continue?',
      confirmLabel: 'Load demo',
      danger: true,
    );
    if (!ok) return;
    try {
      await _repo.seedDemoData();
      if (!mounted) return;
      _initialised = false; // re-hydrate fields from new settings
      showToast(context, 'Demo data loaded');
    } catch (e) {
      if (!mounted) return;
      showError(context, 'Could not load demo data: $e');
    }
  }

  Future<void> _clearAll(String storeName) async {
    final target = storeName.trim().isEmpty ? 'DELETE' : storeName.trim();
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => _TypeToConfirmDialog(
            title: 'Clear all data',
            message:
                'This permanently deletes every product, salesperson, shop and transaction. Your store settings are kept. This cannot be undone — make sure you have a backup first.',
            confirmLabel: 'Clear everything',
            target: target,
            fieldLabel: 'Type "$target" to confirm',
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await _repo.clearAllData();
      if (!mounted) return;
      showToast(context, 'All data cleared');
    } catch (e) {
      if (!mounted) return;
      showError(context, 'Could not clear data: $e');
    }
  }

  Widget _field(String label, TextEditingController controller,
      {TextInputType? keyboard,
      bool digitsOnly = false,
      required VoidCallback onSave}) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      inputFormatters:
          digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          tooltip: 'Save',
          icon: Icon(Icons.check, color: AppColors.positive),
          onPressed: onSave,
        ),
      ),
      onSubmitted: (_) => onSave(),
    );
  }

  Widget _actionRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final color = danger ? AppColors.danger : AppColors.ink;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(color: color))),
            Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// A destructive-action dialog that only enables its confirm button once the
/// user types the required [target] text. Pops true on confirm.
class _TypeToConfirmDialog extends StatefulWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final String target;
  final String fieldLabel;
  const _TypeToConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.target,
    required this.fieldLabel,
  });

  @override
  State<_TypeToConfirmDialog> createState() => _TypeToConfirmDialogState();
}

class _TypeToConfirmDialogState extends State<_TypeToConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _matches =>
      _controller.text.trim().toLowerCase() ==
      widget.target.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.message,
              style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: widget.fieldLabel),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: _matches ? () => Navigator.pop(context, true) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Chips + add field for one managed list kind.
class _ListManager extends ConsumerStatefulWidget {
  final String kind;
  final String title;
  const _ListManager({required this.kind, required this.title});

  @override
  ConsumerState<_ListManager> createState() => _ListManagerState();
}

class _ListManagerState extends ConsumerState<_ListManager> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final v = _controller.text.trim();
    if (v.isEmpty) return;
    await ref.read(repositoryProvider).addListValue(widget.kind, v);
    _controller.clear();
    ref.invalidate(listValuesProvider(widget.kind));
  }

  Future<void> _remove(String value) async {
    await ref.read(repositoryProvider).removeListValue(widget.kind, value);
    ref.invalidate(listValuesProvider(widget.kind));
  }

  @override
  Widget build(BuildContext context) {
    final valuesAsync = ref.watch(listValuesProvider(widget.kind));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          valuesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => Text('$e',
                style: TextStyle(color: AppColors.danger)),
            data: (values) => values.isEmpty
                ? Text('None yet',
                    style: TextStyle(color: AppColors.muted))
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final v in values)
                        Chip(
                          label: Text(v),
                          backgroundColor: AppColors.background,
                          side: BorderSide(color: AppColors.hairline),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () => _remove(v),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(hintText: 'Add value'),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _add,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
