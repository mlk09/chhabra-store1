import '../../core/money.dart';

class Shop {
  const Shop({
    required this.id,
    required this.name,
    this.nameHi,
    this.tagline,
    this.address,
    this.city,
    this.pincode,
    this.phone,
    this.whatsapp,
    this.gstin,
    this.upiId,
    this.upiName,
    this.deliveryPincodes = const [],
    this.deliveryRadiusKm = 3,
    this.deliveryCharge = 0,
    this.freeDeliveryAbove,
    this.minOrder = 0,
    this.isOpen = true,
    this.holidayMode = false,
    this.holidayNote,
    this.timeSlots = defaultSlots,
    this.slotLeadMinutes = 60,
    this.deliveryEnabled = true,
    this.pickupEnabled = true,
    this.codEnabled = true,
    this.upiDirectEnabled = true,
    this.gatewayEnabled = false,
  });

  static const defaultSlots = ['09:00-12:00', '12:00-15:00', '15:00-18:00', '18:00-21:00'];

  final String id;
  final String name;
  final String? nameHi;
  final String? tagline;
  final String? address;
  final String? city;
  final String? pincode;
  final String? phone;
  final String? whatsapp;
  final String? gstin;
  final String? upiId;
  final String? upiName;
  final List<String> deliveryPincodes;
  final double deliveryRadiusKm;
  final Paise deliveryCharge;
  final Paise? freeDeliveryAbove;
  final Paise minOrder;
  final bool isOpen;
  final bool holidayMode;
  final String? holidayNote;

  /// Delivery/pickup windows like "09:00-12:00" (shop's local time, India).
  final List<String> timeSlots;

  /// A slot today must start at least this many minutes from now.
  final int slotLeadMinutes;
  final bool deliveryEnabled;
  final bool pickupEnabled;
  final bool codEnabled;
  final bool upiDirectEnabled;
  final bool gatewayEnabled;

  bool get takingOrders => isOpen && !holidayMode;

  factory Shop.fromJson(Map<String, dynamic> j) => Shop(
    id: j['id'] as String,
    name: j['name'] as String,
    nameHi: j['name_hi'] as String?,
    tagline: j['tagline'] as String?,
    address: j['address'] as String?,
    city: j['city'] as String?,
    pincode: j['pincode'] as String?,
    phone: j['phone'] as String?,
    whatsapp: j['whatsapp'] as String?,
    gstin: j['gstin'] as String?,
    upiId: j['upi_id'] as String?,
    upiName: j['upi_name'] as String?,
    deliveryPincodes: (j['delivery_pincodes'] as List?)?.cast<String>() ?? const [],
    deliveryRadiusKm: (j['delivery_radius_km'] as num?)?.toDouble() ?? 3,
    deliveryCharge: paiseFromJson(j['delivery_charge']),
    freeDeliveryAbove: j['free_delivery_above'] == null ? null : paiseFromJson(j['free_delivery_above']),
    minOrder: paiseFromJson(j['min_order']),
    isOpen: j['is_open'] as bool? ?? true,
    holidayMode: j['holiday_mode'] as bool? ?? false,
    holidayNote: j['holiday_note'] as String?,
    timeSlots: (j['time_slots'] as List?)?.whereType<String>().toList() ?? defaultSlots,
    slotLeadMinutes: (j['slot_lead_minutes'] as num?)?.toInt() ?? 60,
    deliveryEnabled: j['delivery_enabled'] as bool? ?? true,
    pickupEnabled: j['pickup_enabled'] as bool? ?? true,
    codEnabled: j['cod_enabled'] as bool? ?? true,
    upiDirectEnabled: j['upi_direct_enabled'] as bool? ?? true,
    gatewayEnabled: j['gateway_enabled'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'name_hi': nameHi,
    'tagline': tagline,
    'address': address,
    'city': city,
    'pincode': pincode,
    'phone': phone,
    'whatsapp': whatsapp,
    'gstin': gstin,
    'upi_id': upiId,
    'upi_name': upiName,
    'delivery_pincodes': deliveryPincodes,
    'delivery_radius_km': deliveryRadiusKm,
    'delivery_charge': paiseToJson(deliveryCharge),
    'free_delivery_above': freeDeliveryAbove == null ? null : paiseToJson(freeDeliveryAbove!),
    'min_order': paiseToJson(minOrder),
    'is_open': isOpen,
    'holiday_mode': holidayMode,
    'holiday_note': holidayNote,
    'time_slots': timeSlots,
    'slot_lead_minutes': slotLeadMinutes,
    'delivery_enabled': deliveryEnabled,
    'pickup_enabled': pickupEnabled,
    'cod_enabled': codEnabled,
    'upi_direct_enabled': upiDirectEnabled,
    'gateway_enabled': gatewayEnabled,
  };

  Shop copyWithJson(Map<String, dynamic> changes) => Shop.fromJson({...toJson(), ...changes});

  /// Fields the shop-settings screen may change (id/slug are fixed).
  Map<String, dynamic> toEditableJson() => toJson()..remove('id');
}
