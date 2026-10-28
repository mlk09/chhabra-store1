import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../data/models/member.dart';
import '../../data/models/shop.dart';
import '../../domain/slots.dart';

/// Shop name, address, contact, UPI ID, delivery area and open/closed status.
class ShopSettingsScreen extends ConsumerStatefulWidget {
  const ShopSettingsScreen({super.key});
  @override
  ConsumerState<ShopSettingsScreen> createState() => _ShopSettingsScreenState();
}

class _ShopSettingsScreenState extends ConsumerState<ShopSettingsScreen> {
  final _form = GlobalKey<FormState>();
  Shop? _shop;
  final _c = <String, TextEditingController>{};
  bool _isOpen = true, _holiday = false, _saving = false;
  bool _delivery = true, _pickup = true, _cod = true;
  int _lead = 60;
  final _slots = <String>{};

  static const _slotChoices = [
    '07:00-09:00',
    '09:00-12:00',
    '12:00-15:00',
    '15:00-18:00',
    '18:00-21:00',
    '21:00-23:00',
  ];

  TextEditingController _ctl(String key) => _c.putIfAbsent(key, TextEditingController.new);

  void _load(Shop s) {
    if (_shop != null) return;
    _shop = s;
    _ctl('name').text = s.name;
    _ctl('name_hi').text = s.nameHi ?? '';
    _ctl('tagline').text = s.tagline ?? '';
    _ctl('address').text = s.address ?? '';
    _ctl('city').text = s.city ?? '';
    _ctl('pincode').text = s.pincode ?? '';
    _ctl('phone').text = s.phone ?? '';
    _ctl('whatsapp').text = s.whatsapp ?? '';
    _ctl('gstin').text = s.gstin ?? '';
    _ctl('upi_id').text = s.upiId ?? '';
    _ctl('upi_name').text = s.upiName ?? '';
    _ctl('pincodes').text = s.deliveryPincodes.join(', ');
    _ctl('radius').text = s.deliveryRadiusKm.toStringAsFixed(s.deliveryRadiusKm % 1 == 0 ? 0 : 1);
    _ctl('charge').text = rupeesText(s.deliveryCharge);
    _ctl('free_above').text = s.freeDeliveryAbove == null ? '' : rupeesText(s.freeDeliveryAbove!);
    _ctl('min_order').text = rupeesText(s.minOrder);
    _ctl('holiday_note').text = s.holidayNote ?? '';
    _isOpen = s.isOpen;
    _holiday = s.holidayMode;
    _delivery = s.deliveryEnabled;
    _pickup = s.pickupEnabled;
    _cod = s.codEnabled;
    _lead = s.slotLeadMinutes;
    _slots.addAll(s.timeSlots);
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _v(String key) => _ctl(key).text.trim().isEmpty ? null : _ctl(key).text.trim();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final s = _shop!;
    if (_slots.isEmpty) {
      showSnack(context, context.tr('Keep at least one time slot.', 'कम से कम एक समय रखें।'), error: true);
      return;
    }
    if (!_delivery && !_pickup) {
      showSnack(context, context.tr('Turn on delivery or pickup.', 'डिलीवरी या पिकअप चालू रखें।'), error: true);
      return;
    }
    final updated = s.copyWithJson({
      'name': _v('name')!,
      'name_hi': _v('name_hi'),
      'tagline': _v('tagline'),
      'address': _v('address'),
      'city': _v('city'),
      'pincode': _v('pincode'),
      'phone': _v('phone')?.replaceAll(RegExp(r'[\s-]'), ''),
      'whatsapp': _v('whatsapp')?.replaceAll(RegExp(r'[\s-]'), ''),
      'gstin': _v('gstin')?.toUpperCase(),
      'upi_id': _v('upi_id'),
      'upi_name': _v('upi_name'),
      'delivery_pincodes': (_v('pincodes') ?? '').split(RegExp(r'[,\s]+')).where((p) => p.isNotEmpty).toList(),
      'delivery_radius_km': double.tryParse(_ctl('radius').text) ?? 3,
      'delivery_charge': paiseToJson(parseRupees(_ctl('charge').text) ?? 0),
      'free_delivery_above': parseRupees(_ctl('free_above').text) == null
          ? null
          : paiseToJson(parseRupees(_ctl('free_above').text)!),
      'min_order': paiseToJson(parseRupees(_ctl('min_order').text) ?? 0),
      'is_open': _isOpen,
      'holiday_mode': _holiday,
      'holiday_note': _v('holiday_note'),
      'delivery_enabled': _delivery,
      'pickup_enabled': _pickup,
      'cod_enabled': _cod,
      'slot_lead_minutes': _lead,
      'time_slots': (_slots.toList()..sort()),
    });

    setState(() => _saving = true);
    try {
      await ref.read(catalogProvider.notifier).updateShop(updated);
      if (!mounted) return;
      showSnack(context, context.tr('Shop details saved ✓', 'दुकान की जानकारी सेव ✓'));
      context.pop();
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    String key,
    String label, {
    String? hint,
    String? helper,
    TextInputType? type,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: _ctl(key),
      keyboardType: type,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label, hintText: hint, helperText: helper, helperMaxLines: 3),
      validator: validator,
    ),
  );

  String? Function(String?) _pattern(RegExp re, String msg, {bool required = false}) => (v) {
    final s = (v ?? '').trim().replaceAll(RegExp(r'[\s-]'), '');
    if (s.isEmpty) return required ? context.tr('Required', 'ज़रूरी') : null;
    return re.hasMatch(s) ? null : msg;
  };

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider).value;
    final canEdit = ref.watch(sessionProvider).value?.can(Perm.settings) ?? false;
    if (catalog == null) return const Scaffold(body: LoadingView());
    if (!canEdit) {
      return Scaffold(
        appBar: AppBar(),
        body: MessageView(
          icon: Icons.lock_outline,
          title: context.tr('Only the owner can change shop details', 'दुकान की जानकारी सिर्फ़ मालिक बदल सकता है'),
        ),
      );
    }
    _load(catalog.shop);
    final t = Theme.of(context);
    final phoneRe = RegExp(r'^\+?[0-9]{10,13}$');
    final moneyType = const TextInputType.numberWithOptions(decimal: true);
    String? money(String? v) =>
        (v == null || v.trim().isEmpty || parseRupees(v) != null) ? null : context.tr('Enter an amount', 'रकम लिखें');

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Shop details', 'दुकान की जानकारी'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(onPressed: _saving ? null : _save, child: Text(context.tr('Save', 'सेव करें'))),
        ),
      ),
      body: Form(
        key: _form,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: Text(context.tr('Shop is open', 'दुकान खुली है')),
                        subtitle: Text(
                          context.tr(
                            'Turn off to stop new online orders for now',
                            'अभी नए ऑनलाइन ऑर्डर रोकने के लिए बंद करें',
                          ),
                        ),
                        value: _isOpen,
                        onChanged: (v) => setState(() => _isOpen = v),
                      ),
                      SwitchListTile(
                        title: Text(context.tr('Holiday mode', 'छुट्टी मोड')),
                        value: _holiday,
                        onChanged: (v) => setState(() => _holiday = v),
                      ),
                      if (_holiday)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: _field(
                            'holiday_note',
                            context.tr('Message for customers', 'ग्राहकों के लिए संदेश'),
                            hint: context.tr('Closed till Monday for Diwali', 'दिवाली के लिए सोमवार तक बंद'),
                          ),
                        ),
                    ],
                  ),
                ),
                SectionTitle(context.tr('Shop', 'दुकान')),
                _field(
                  'name',
                  context.tr('Shop name *', 'दुकान का नाम *'),
                  validator: (v) => (v?.trim().length ?? 0) >= 2 ? null : context.tr('Required', 'ज़रूरी'),
                ),
                _field('name_hi', context.tr('Shop name in Hindi', 'दुकान का हिंदी नाम')),
                _field('tagline', context.tr('Tagline', 'टैगलाइन')),
                _field('address', context.tr('Address', 'पता'), maxLines: 2),
                Row(
                  children: [
                    Expanded(child: _field('city', context.tr('City', 'शहर'))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(
                        'pincode',
                        context.tr('Pincode', 'पिनकोड'),
                        type: TextInputType.number,
                        validator: _pattern(RegExp(r'^[1-9][0-9]{5}$'), context.tr('6 digits', '6 अंक')),
                      ),
                    ),
                  ],
                ),
                _field(
                  'phone',
                  context.tr('Phone', 'फ़ोन'),
                  type: TextInputType.phone,
                  validator: _pattern(phoneRe, context.tr('10-digit number', '10 अंकों का नंबर')),
                ),
                _field(
                  'whatsapp',
                  context.tr('WhatsApp number', 'व्हाट्सऐप नंबर'),
                  type: TextInputType.phone,
                  validator: _pattern(phoneRe, context.tr('10-digit number', '10 अंकों का नंबर')),
                ),
                _field(
                  'gstin',
                  context.tr('GSTIN (optional)', 'GSTIN (वैकल्पिक)'),
                  validator: _pattern(RegExp(r'^[0-9]{2}[A-Za-z0-9]{13}$'), context.tr('15 characters', '15 अक्षर')),
                ),
                SectionTitle(context.tr('UPI payments', 'UPI पेमेंट')),
                _field(
                  'upi_id',
                  context.tr('Shop UPI ID', 'दुकान की UPI ID'),
                  hint: 'yourname@okaxis',
                  helper: context.tr(
                    'Customers pay to this ID from GPay / PhonePe / Paytm. Copy it exactly from your UPI app.',
                    'ग्राहक GPay / PhonePe / Paytm से इसी ID पर पेमेंट करेंगे। अपने UPI ऐप से ठीक-ठीक कॉपी करें।',
                  ),
                  validator: _pattern(
                    RegExp(r'^[a-zA-Z0-9._-]{2,100}@[a-zA-Z]{2,64}$'),
                    context.tr('Looks like name@bank', 'ऐसा दिखना चाहिए: name@bank'),
                  ),
                ),
                _field('upi_name', context.tr('Name shown in UPI app', 'UPI ऐप में दिखने वाला नाम')),
                SectionTitle(context.tr('Delivery', 'डिलीवरी')),
                _field(
                  'pincodes',
                  context.tr('Delivery pincodes', 'डिलीवरी पिनकोड'),
                  hint: '132001, 132116',
                  validator: (v) =>
                      (v ?? '')
                          .split(RegExp(r'[,\s]+'))
                          .where((p) => p.isNotEmpty)
                          .every((p) => RegExp(r'^[1-9][0-9]{5}$').hasMatch(p))
                      ? null
                      : context.tr('6-digit pincodes, separated by commas', '6 अंकों के पिनकोड, कॉमा से अलग'),
                ),
                _field(
                  'radius',
                  context.tr('Delivery distance (km)', 'डिलीवरी दूरी (किमी)'),
                  type: moneyType,
                  validator: (v) =>
                      ((double.tryParse(v ?? '') ?? -1) >= 0 && (double.tryParse(v ?? '') ?? 99) <= 50) ? null : '0–50',
                ),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        'charge',
                        context.tr('Delivery charge ₹', 'डिलीवरी चार्ज ₹'),
                        type: moneyType,
                        validator: money,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(
                        'free_above',
                        context.tr('Free above ₹', 'इससे ऊपर फ्री ₹'),
                        type: moneyType,
                        validator: money,
                      ),
                    ),
                  ],
                ),
                _field(
                  'min_order',
                  context.tr('Minimum order ₹', 'कम से कम ऑर्डर ₹'),
                  type: moneyType,
                  validator: money,
                ),
                SectionTitle(context.tr('Online orders', 'ऑनलाइन ऑर्डर')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.tr('Home delivery', 'होम डिलीवरी')),
                  value: _delivery,
                  onChanged: (v) => setState(() => _delivery = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.tr('Pickup from shop', 'दुकान से पिकअप')),
                  value: _pickup,
                  onChanged: (v) => setState(() => _pickup = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.tr('Cash / pay on delivery', 'कैश / डिलीवरी पर भुगतान')),
                  subtitle: Text(
                    context.tr('UPI and online payment come in the next update', 'UPI और ऑनलाइन भुगतान अगले अपडेट में'),
                  ),
                  value: _cod,
                  onChanged: (v) => setState(() => _cod = v),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr('Time slots customers can choose', 'ग्राहक कौन सा समय चुन सकते हैं'),
                  style: t.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final slot in {..._slotChoices, ..._slots}.toList()..sort())
                      FilterChip(
                        label: Text(prettySlot(slot)),
                        selected: _slots.contains(slot),
                        onSelected: (on) => setState(() => on ? _slots.add(slot) : _slots.remove(slot)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _lead,
                  decoration: InputDecoration(
                    labelText: context.tr('Earliest slot today starts after', 'आज का सबसे पहला स्लॉट कितनी देर बाद'),
                  ),
                  items: [
                    for (final m in [30, 60, 90, 120, 180])
                      DropdownMenuItem(value: m, child: Text(context.tr('$m minutes', '$m मिनट'))),
                  ],
                  onChanged: (v) => setState(() => _lead = v ?? _lead),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
