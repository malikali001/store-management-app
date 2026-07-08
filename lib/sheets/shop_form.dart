import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/ui.dart';
import '../data/repository.dart';
import '../domain/models.dart';

/// Add or edit a shop (external customer). Shops are retailers who buy goods
/// to resell — distinct from salespersons (hired staff).
Future<void> showShopForm(BuildContext context, WidgetRef ref, {Shop? existing}) {
  return showAppSheet<void>(context, _ShopForm(existing: existing));
}

class _ShopForm extends ConsumerStatefulWidget {
  final Shop? existing;
  const _ShopForm({this.existing});

  @override
  ConsumerState<_ShopForm> createState() => _ShopFormState();
}

class _ShopFormState extends ConsumerState<_ShopForm> {
  late final TextEditingController _name;
  late final TextEditingController _owner;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _note;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _name = TextEditingController(text: s?.name ?? '');
    _owner = TextEditingController(text: s?.ownerName ?? '');
    _phone = TextEditingController(text: s?.phone ?? '');
    _address = TextEditingController(text: s?.address ?? '');
    _note = TextEditingController(text: s?.note ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _owner.dispose();
    _phone.dispose();
    _address.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repo = ref.read(repositoryProvider);

    final name = _name.text.trim();
    if (name.isEmpty) {
      showError(context, 'Enter a shop name.');
      return;
    }

    final Shop shop;
    if (widget.existing != null) {
      shop = widget.existing!.copyWith(
        name: name,
        ownerName: _owner.text.trim(),
        phone: _phone.text.trim(),
        address: _address.text.trim(),
        note: _note.text.trim(),
      );
    } else {
      shop = Shop(
        id: newId(),
        name: name,
        ownerName: _owner.text.trim(),
        phone: _phone.text.trim(),
        address: _address.text.trim(),
        note: _note.text.trim(),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
    }

    try {
      await repo.upsertShop(shop);
    } catch (e) {
      if (mounted) showError(context, 'Something went wrong. Please try again.');
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
    showToast(context, _isEdit ? 'Shop updated' : 'Shop added');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(_isEdit ? 'Edit shop' : 'Add shop'),
        TextField(
          key: const Key('shop_name'),
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Shop name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _owner,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Owner name (optional)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone (optional)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _address,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Address (optional)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('shop_save'),
          onPressed: _save,
          child: Text(_isEdit ? 'Save changes' : 'Add shop'),
        ),
      ],
    );
  }
}
