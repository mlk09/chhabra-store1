import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/order_state.dart';
import '../../core/order_text.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../data/backend.dart';
import '../../data/models/order.dart';
import '../../data/models/shop.dart';
import '../../domain/slots.dart';
import 'cart_screen.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});
  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  /// One id per checkout: a double tap or a retry can never create two orders.
  final _clientRef = const Uuid().v4();
  final _note = TextEditingController();
  String? _addressId;
  SlotChoice? _slot;
  String _payment = 'cod';
  bool _placing = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _place(Quote quote, Shop shop) async {
    final choice = ref.read(checkoutChoiceProvider);
    final cart = ref.read(cartProvider);
    if (choice.fulfilment == Fulfilment.delivery && _addressId == null) {
      showSnack(context, context.tr('Please choose a delivery address.', 'डिलीवरी का पता चुनें।'), error: true);
      return;
    }
    if (_slot == null) {
      showSnack(context, context.tr('Please choose a time slot.', 'समय चुनें।'), error: true);
      return;
    }
    setState(() => _placing = true);
    try {
      final id = await ref
          .read(backendProvider)
          .placeOrder(
            OrderRequest(
              items: [for (final e in cart.entries) CartItem(e.key, e.value)],
              fulfilment: choice.fulfilment,
              paymentMethod: _payment,
              slotDate: _slot!.date,
              slot: _slot!.slot,
              addressId: choice.fulfilment == Fulfilment.delivery ? _addressId : null,
              coupon: choice.coupon,
              note: _note.text.trim().isEmpty ? null : _note.text.trim(),
              clientRef: _clientRef,
              expectedTotal: quote.total,
            ),
          );
      ref.read(cartProvider.notifier).clear();
      ref.read(checkoutChoiceProvider.notifier).setCoupon(null);
      unawaitedRefresh();
      if (!mounted) return;
      context.go('/orders/$id?placed=1');
    } catch (e) {
      if (!mounted) return;
      final code = e is AppException ? e.code : null;
      if (code == 'price_changed' || code == 'items_changed' || (code ?? '').startsWith('coupon_')) {
        ref.invalidate(quoteProvider);
        await ref.read(catalogProvider.notifier).refresh(silent: true);
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('Order not placed', 'ऑर्डर नहीं हुआ')),
          content: Text(orderErrorText(ctx, e)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      if (mounted && code == 'items_changed') context.pop();
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  void unawaitedRefresh() => ref.read(catalogProvider.notifier).refresh(silent: true);

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider).value;
    final quote = ref.watch(quoteProvider).value;
    final choice = ref.watch(checkoutChoiceProvider);
    final addresses = ref.watch(addressesProvider);
    final t = Theme.of(context);
    if (catalog == null || quote == null) return const Scaffold(body: LoadingView());
    final shop = catalog.shop;
    final slots = upcomingSlots(shop, DateTime.now());
    _slot ??= slots.firstOrNull;
    final list = addresses.value ?? const <Address>[];
    if (_addressId == null || !list.any((a) => a.id == _addressId)) {
      _addressId = (list.where((a) => a.isDefault).firstOrNull ?? list.lastOrNull)?.id;
    }
    final payments = <(String, String, IconData)>[
      if (shop.codEnabled)
        (
          'cod',
          choice.fulfilment == Fulfilment.pickup
              ? context.tr('Pay at the shop (cash / UPI)', 'दुकान पर भुगतान (कैश / UPI)')
              : context.tr('Pay on delivery (cash / UPI)', 'डिलीवरी पर भुगतान (कैश / UPI)'),
          Icons.payments_outlined,
        ),
    ];
    if (!payments.any((p) => p.$1 == _payment) && payments.isNotEmpty) _payment = payments.first.$1;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Checkout', 'ऑर्डर करें'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _placing || payments.isEmpty || !shop.takingOrders ? null : () => _place(quote, shop),
            child: _placing
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(
                    context.tr('Place order · ${formatMoney(quote.total)}', 'ऑर्डर करें · ${formatMoney(quote.total)}'),
                  ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (choice.fulfilment == Fulfilment.delivery) ...[
            SectionTitle(context.tr('Deliver to', 'डिलीवरी का पता')),
            if (addresses.isLoading) const LoadingView(),
            RadioGroup<String>(
              groupValue: _addressId,
              onChanged: (v) => setState(() => _addressId = v),
              child: Column(
                children: [
                  for (final a in list)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: RadioListTile<String>(
                        value: a.id,
                        title: Text('${a.label ?? context.tr('Address', 'पता')} · ${a.name}'),
                        subtitle: Text('${a.oneLine}\n${a.phone}'),
                        isThreeLine: true,
                        secondary: IconButton(
                          tooltip: context.tr('Edit', 'बदलें'),
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => editAddress(context, ref, a, shop),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final a = await editAddress(context, ref, null, shop);
                if (a != null) setState(() => _addressId = a.id);
              },
              icon: const Icon(Icons.add_location_alt_outlined),
              label: Text(context.tr('Add new address', 'नया पता जोड़ें')),
            ),
          ] else ...[
            SectionTitle(context.tr('Pick up from', 'यहाँ से लें')),
            Card(
              child: ListTile(
                leading: const Icon(Icons.storefront_rounded),
                title: Text(context.pick(shop.name, shop.nameHi)),
                subtitle: Text([shop.address, shop.city, shop.phone].whereType<String>().join(', ')),
              ),
            ),
          ],
          SectionTitle(
            choice.fulfilment == Fulfilment.delivery
                ? context.tr('Delivery time', 'डिलीवरी का समय')
                : context.tr('Pickup time', 'पिकअप का समय'),
          ),
          if (slots.isEmpty)
            Text(
              context.tr(
                'No time slots available. Please contact the shop.',
                'कोई समय उपलब्ध नहीं। दुकान से बात करें।',
              ),
            )
          else
            _SlotPicker(slots: slots, selected: _slot, onPick: (s) => setState(() => _slot = s)),
          SectionTitle(context.tr('Payment', 'भुगतान')),
          if (payments.isEmpty)
            Text(
              context.tr('Online ordering is paused by the shop.', 'दुकान ने ऑनलाइन ऑर्डर अभी रोके हैं।'),
              style: const TextStyle(color: Brand.red),
            ),
          RadioGroup<String>(
            groupValue: _payment,
            onChanged: (v) => setState(() => _payment = v ?? _payment),
            child: Column(
              children: [
                for (final p in payments)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: RadioListTile<String>(value: p.$1, title: Text(p.$2), secondary: Icon(p.$3)),
                  ),
              ],
            ),
          ),
          Text(
            context.tr('Online UPI payment is coming in the next update.', 'ऑनलाइन UPI भुगतान अगले अपडेट में आएगा।'),
            style: t.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            maxLength: 300,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: context.tr('Note for the shop (optional)', 'दुकान के लिए नोट (वैकल्पिक)'),
              hintText: context.tr('e.g. Ring the bell, call before coming', 'जैसे: घंटी बजाएँ, आने से पहले फ़ोन करें'),
            ),
          ),
          BillCard(quote: quote),
        ],
      ),
    );
  }
}

class _SlotPicker extends StatelessWidget {
  const _SlotPicker({required this.slots, required this.selected, required this.onPick});
  final List<SlotChoice> slots;
  final SlotChoice? selected;
  final ValueChanged<SlotChoice> onPick;

  String _day(BuildContext context, DateTime d) {
    final today = shopClock(DateTime.now());
    final t0 = DateTime.utc(today.year, today.month, today.day);
    final diff = d.difference(t0).inDays;
    if (diff == 0) return context.tr('Today', 'आज');
    if (diff == 1) return context.tr('Tomorrow', 'कल');
    return DateFormat('EEE, d MMM').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final days = <DateTime, List<SlotChoice>>{};
    for (final s in slots) {
      days.putIfAbsent(s.date, () => []).add(s);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in days.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: Text(_day(context, e.key), style: Theme.of(context).textTheme.titleSmall),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in e.value)
                ChoiceChip(label: Text(prettySlot(s.slot)), selected: selected == s, onSelected: (_) => onPick(s)),
            ],
          ),
        ],
      ],
    );
  }
}

/// Add or edit an address in a bottom sheet. Returns the saved address.
Future<Address?> editAddress(BuildContext context, WidgetRef ref, Address? existing, Shop shop) =>
    showModalBottomSheet<Address>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddressSheet(existing: existing, shop: shop),
    );

class _AddressSheet extends ConsumerStatefulWidget {
  const _AddressSheet({this.existing, required this.shop});
  final Address? existing;
  final Shop shop;
  @override
  ConsumerState<_AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends ConsumerState<_AddressSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? ref.read(sessionProvider).value?.user?.name);
  late final _phone = TextEditingController(
    text: widget.existing?.phone ?? ref.read(sessionProvider).value?.user?.phone,
  );
  late final _line1 = TextEditingController(text: widget.existing?.line1);
  late final _line2 = TextEditingController(text: widget.existing?.line2);
  late final _landmark = TextEditingController(text: widget.existing?.landmark);
  late final _pincode = TextEditingController(text: widget.existing?.pincode ?? widget.shop.pincode);
  late String _label = widget.existing?.label ?? 'Home';
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _line1, _line2, _landmark, _pincode]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(addressesProvider.notifier)
          .save(
            Address(
              id: widget.existing?.id ?? const Uuid().v4(),
              label: _label,
              name: _name.text.trim(),
              phone: _phone.text.replaceAll(RegExp(r'[\s-]'), ''),
              line1: _line1.text.trim(),
              line2: _opt(_line2),
              landmark: _opt(_landmark),
              pincode: _pincode.text.trim(),
              isDefault: true,
            ),
          );
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pins = widget.shop.deliveryPincodes;
    final pin = _pincode.text.trim();
    final outside = pins.isNotEmpty && RegExp(r'^[1-9][0-9]{5}$').hasMatch(pin) && !pins.contains(pin);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.existing == null
                    ? context.tr('New address', 'नया पता')
                    : context.tr('Edit address', 'पता बदलें'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final l in ['Home', 'Work', 'Other'])
                    ChoiceChip(
                      label: Text(switch (l) {
                        'Home' => context.tr('Home', 'घर'),
                        'Work' => context.tr('Work', 'काम'),
                        _ => context.tr('Other', 'अन्य'),
                      }),
                      selected: _label == l,
                      onSelected: (_) => setState(() => _label = l),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: context.tr('Name *', 'नाम *')),
                validator: (v) => (v?.trim().length ?? 0) >= 2 ? null : context.tr('Required', 'ज़रूरी'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: context.tr('Mobile number *', 'मोबाइल नंबर *')),
                validator: (v) => RegExp(r'^\+?[0-9]{10,13}$').hasMatch((v ?? '').replaceAll(RegExp(r'[\s-]'), ''))
                    ? null
                    : context.tr('10-digit number', '10 अंकों का नंबर'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _line1,
                decoration: InputDecoration(labelText: context.tr('House no., street *', 'मकान नं., गली *')),
                validator: (v) => (v?.trim().length ?? 0) >= 3 ? null : context.tr('Required', 'ज़रूरी'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _line2,
                decoration: InputDecoration(labelText: context.tr('Area / colony', 'इलाका / कॉलोनी')),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _landmark,
                decoration: InputDecoration(labelText: context.tr('Landmark', 'पास में')),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _pincode,
                keyboardType: TextInputType.number,
                maxLength: 6,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: context.tr('Pincode *', 'पिनकोड *'),
                  helperText: outside
                      ? context.tr(
                          'We deliver only to ${pins.join(', ')} — you can still choose pickup.',
                          'डिलीवरी सिर्फ़ ${pins.join(', ')} में — पिकअप चुन सकते हैं।',
                        )
                      : null,
                  helperStyle: const TextStyle(color: Brand.saffronDeep),
                  helperMaxLines: 2,
                ),
                validator: (v) =>
                    RegExp(r'^[1-9][0-9]{5}$').hasMatch(v?.trim() ?? '') ? null : context.tr('6 digits', '6 अंक'),
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: _saving ? null : _save, child: Text(context.tr('Save address', 'पता सेव करें'))),
              if (widget.existing != null)
                TextButton(
                  onPressed: () async {
                    await ref.read(addressesProvider.notifier).delete(widget.existing!.id);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Text(context.tr('Delete address', 'पता हटाएँ'), style: const TextStyle(color: Brand.red)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
