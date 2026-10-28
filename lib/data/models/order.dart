import '../../core/money.dart';
import '../../core/units.dart';

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
double _qty(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

enum Fulfilment { delivery, pickup }

enum OfferKind {
  productPercent('product_percent'),
  productFlat('product_flat'),
  categoryPercent('category_percent'),
  cartFlat('cart_flat'),
  cartPercent('cart_percent'),
  freeDelivery('free_delivery'),
  bxgy('bxgy');

  const OfferKind(this.code);
  final String code;
  static OfferKind parse(String? c) => values.firstWhere((k) => k.code == c, orElse: () => OfferKind.cartFlat);

  bool get forProduct => this == productPercent || this == productFlat || this == bxgy;
  bool get forCart => this == cartFlat || this == cartPercent || this == freeDelivery;
  bool get usesPercent => this == productPercent || this == categoryPercent || this == cartPercent;
  bool get usesAmount => this == productFlat || this == cartFlat;
}

class Offer {
  const Offer({
    required this.id,
    required this.title,
    this.titleHi,
    required this.kind,
    this.productId,
    this.categoryId,
    this.percent,
    this.amount,
    this.minOrder = 0,
    this.maxDiscount,
    this.buyQty,
    this.getQty,
    this.startsAt,
    this.endsAt,
    this.isActive = true,
    this.createdAt,
  });

  final String id;
  final String title;
  final String? titleHi;
  final OfferKind kind;
  final String? productId;
  final String? categoryId;
  final double? percent;
  final Paise? amount;
  final Paise minOrder;
  final Paise? maxDiscount;
  final int? buyQty;
  final int? getQty;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool isActive;
  final DateTime? createdAt;

  bool liveAt(DateTime now) =>
      isActive && (startsAt == null || !startsAt!.isAfter(now)) && (endsAt == null || endsAt!.isAfter(now));

  factory Offer.fromJson(Map<String, dynamic> j) => Offer(
    id: j['id'] as String,
    title: j['title'] as String,
    titleHi: j['title_hi'] as String?,
    kind: OfferKind.parse(j['kind'] as String?),
    productId: j['product_id'] as String?,
    categoryId: j['category_id'] as String?,
    percent: (j['percent'] as num?)?.toDouble(),
    amount: j['amount'] == null ? null : paiseFromJson(j['amount']),
    minOrder: paiseFromJson(j['min_order']),
    maxDiscount: j['max_discount'] == null ? null : paiseFromJson(j['max_discount']),
    buyQty: (j['buy_qty'] as num?)?.toInt(),
    getQty: (j['get_qty'] as num?)?.toInt(),
    startsAt: _date(j['starts_at']),
    endsAt: _date(j['ends_at']),
    isActive: j['is_active'] as bool? ?? true,
    createdAt: _date(j['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'title_hi': titleHi,
    'kind': kind.code,
    'product_id': productId,
    'category_id': categoryId,
    'percent': percent,
    'amount': amount == null ? null : paiseToJson(amount!),
    'min_order': paiseToJson(minOrder),
    'max_discount': maxDiscount == null ? null : paiseToJson(maxDiscount!),
    'buy_qty': buyQty,
    'get_qty': getQty,
    'starts_at': startsAt?.toUtc().toIso8601String(),
    'ends_at': endsAt?.toUtc().toIso8601String(),
    'is_active': isActive,
    'created_at': createdAt?.toUtc().toIso8601String(),
  };
}

enum CouponKind {
  percent,
  flat,
  freeDelivery;

  String get code => this == freeDelivery ? 'free_delivery' : name;
  static CouponKind parse(String? c) => values.firstWhere((k) => k.code == c, orElse: () => CouponKind.flat);
}

class Coupon {
  const Coupon({
    required this.id,
    required this.code,
    this.title,
    required this.kind,
    this.value = 0,
    this.maxDiscount,
    this.minOrder = 0,
    this.startsAt,
    this.endsAt,
    this.usageLimit,
    this.perUserLimit = 1,
    this.usedCount = 0,
    this.isPublic = false,
    this.isActive = true,
  });

  final String id;
  final String code;
  final String? title;
  final CouponKind kind;

  /// Percent for [CouponKind.percent], paise for [CouponKind.flat].
  final num value;
  final Paise? maxDiscount;
  final Paise minOrder;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int? usageLimit;
  final int perUserLimit;
  final int usedCount;
  final bool isPublic;
  final bool isActive;

  factory Coupon.fromJson(Map<String, dynamic> j) {
    final kind = CouponKind.parse(j['kind'] as String?);
    return Coupon(
      id: j['id'] as String,
      code: j['code'] as String,
      title: j['title'] as String?,
      kind: kind,
      value: kind == CouponKind.flat ? paiseFromJson(j['value']) : (j['value'] as num? ?? 0).toDouble(),
      maxDiscount: j['max_discount'] == null ? null : paiseFromJson(j['max_discount']),
      minOrder: paiseFromJson(j['min_order']),
      startsAt: _date(j['starts_at']),
      endsAt: _date(j['ends_at']),
      usageLimit: (j['usage_limit'] as num?)?.toInt(),
      perUserLimit: (j['per_user_limit'] as num?)?.toInt() ?? 1,
      usedCount: (j['used_count'] as num?)?.toInt() ?? 0,
      isPublic: j['is_public'] as bool? ?? false,
      isActive: j['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'title': title,
    'kind': kind.code,
    'value': kind == CouponKind.flat ? paiseToJson(value.toInt()) : value,
    'max_discount': maxDiscount == null ? null : paiseToJson(maxDiscount!),
    'min_order': paiseToJson(minOrder),
    'starts_at': startsAt?.toUtc().toIso8601String(),
    'ends_at': endsAt?.toUtc().toIso8601String(),
    'usage_limit': usageLimit,
    'per_user_limit': perUserLimit,
    'used_count': usedCount,
    'is_public': isPublic,
    'is_active': isActive,
  };
}

/// One line the customer put in the cart.
class CartItem {
  const CartItem(this.variantId, this.qty);
  final String variantId;
  final double qty;
  Map<String, dynamic> toJson() => {'variant_id': variantId, 'qty': qty};
}

class QuoteLine {
  const QuoteLine({
    required this.variantId,
    required this.productId,
    required this.name,
    this.nameHi,
    required this.label,
    required this.unit,
    required this.isLoose,
    required this.qty,
    required this.mrp,
    required this.price,
    required this.lineMrp,
    required this.discount,
    required this.lineTotal,
    this.freeQty = 0,
    this.offer,
  });

  final String variantId;
  final String productId;
  final String name;
  final String? nameHi;
  final String label;
  final SaleUnit unit;
  final bool isLoose;
  final double qty;
  final Paise mrp, price, lineMrp, discount, lineTotal;
  final double freeQty;
  final String? offer;

  factory QuoteLine.fromJson(Map<String, dynamic> j) => QuoteLine(
    variantId: j['variant_id'] as String,
    productId: j['product_id'] as String,
    name: j['name'] as String,
    nameHi: j['name_hi'] as String?,
    label: j['label'] as String,
    unit: SaleUnit.parse(j['unit'] as String?),
    isLoose: j['is_loose'] as bool? ?? false,
    qty: _qty(j['qty']),
    mrp: paiseFromJson(j['mrp']),
    price: paiseFromJson(j['price']),
    lineMrp: paiseFromJson(j['line_mrp']),
    discount: paiseFromJson(j['discount']),
    lineTotal: paiseFromJson(j['line_total']),
    freeQty: _qty(j['free_qty']),
    offer: j['offer'] as String?,
  );
}

class UnavailableLine {
  const UnavailableLine({required this.variantId, required this.reason, this.available = 0});
  final String variantId;

  /// 'unavailable' (hidden/deleted) or 'insufficient' (not enough stock).
  final String reason;
  final double available;

  factory UnavailableLine.fromJson(Map<String, dynamic> j) => UnavailableLine(
    variantId: j['variant_id'] as String,
    reason: j['reason'] as String,
    available: _qty(j['available']),
  );
}

/// The bill for a cart, as calculated by the server (or the demo copy).
class Quote {
  const Quote({
    required this.lines,
    this.unavailable = const [],
    required this.subtotalMrp,
    required this.itemsTotal,
    this.itemDiscount = 0,
    this.cartDiscount = 0,
    this.cartOffer,
    this.couponCode,
    this.couponId,
    this.couponDiscount = 0,
    this.couponError,
    this.couponMinOrder,
    this.deliveryCharge = 0,
    this.deliverySaved = 0,
    required this.total,
    this.savings = 0,
    this.minOrder = 0,
    this.belowMinOrder = false,
  });

  final List<QuoteLine> lines;
  final List<UnavailableLine> unavailable;
  final Paise subtotalMrp, itemsTotal, itemDiscount, cartDiscount;
  final String? cartOffer;
  final String? couponCode, couponId;
  final Paise couponDiscount;
  final String? couponError;
  final Paise? couponMinOrder;
  final Paise deliveryCharge, deliverySaved, total, savings, minOrder;
  final bool belowMinOrder;

  factory Quote.fromJson(Map<String, dynamic> j) => Quote(
    lines: ((j['lines'] as List?) ?? const []).map((l) => QuoteLine.fromJson((l as Map).cast())).toList(),
    unavailable: ((j['unavailable'] as List?) ?? const [])
        .map((l) => UnavailableLine.fromJson((l as Map).cast()))
        .toList(),
    subtotalMrp: paiseFromJson(j['subtotal_mrp']),
    itemsTotal: paiseFromJson(j['items_total']),
    itemDiscount: paiseFromJson(j['item_discount']),
    cartDiscount: paiseFromJson(j['cart_discount']),
    cartOffer: j['cart_offer'] as String?,
    couponCode: j['coupon_code'] as String?,
    couponId: j['coupon_id'] as String?,
    couponDiscount: paiseFromJson(j['coupon_discount']),
    couponError: j['coupon_error'] as String?,
    couponMinOrder: j['coupon_min_order'] == null ? null : paiseFromJson(j['coupon_min_order']),
    deliveryCharge: paiseFromJson(j['delivery_charge']),
    deliverySaved: paiseFromJson(j['delivery_saved']),
    total: paiseFromJson(j['total']),
    savings: paiseFromJson(j['savings']),
    minOrder: paiseFromJson(j['min_order']),
    belowMinOrder: j['below_min_order'] as bool? ?? false,
  );
}

class Address {
  const Address({
    required this.id,
    this.label,
    required this.name,
    required this.phone,
    required this.line1,
    this.line2,
    this.landmark,
    required this.pincode,
    this.isDefault = false,
  });

  final String id;
  final String? label;
  final String name;
  final String phone;
  final String line1;
  final String? line2;
  final String? landmark;
  final String pincode;
  final bool isDefault;

  String get oneLine => [line1, line2, landmark, pincode].whereType<String>().where((s) => s.isNotEmpty).join(', ');

  factory Address.fromJson(Map<String, dynamic> j) => Address(
    id: j['id'] as String,
    label: j['label'] as String?,
    name: j['name'] as String? ?? '',
    phone: j['phone'] as String? ?? '',
    line1: j['line1'] as String? ?? '',
    line2: j['line2'] as String?,
    landmark: j['landmark'] as String?,
    pincode: j['pincode'] as String? ?? '',
    isDefault: j['is_default'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'name': name,
    'phone': phone,
    'line1': line1,
    'line2': line2,
    'landmark': landmark,
    'pincode': pincode,
    'is_default': isDefault,
  };
}

enum OrderStatus {
  newOrder('new'),
  accepted('accepted'),
  packed('packed'),
  outForDelivery('out_for_delivery'),
  readyForPickup('ready_for_pickup'),
  delivered('delivered'),
  cancelled('cancelled');

  const OrderStatus(this.code);
  final String code;
  static OrderStatus parse(String? c) => values.firstWhere((s) => s.code == c, orElse: () => OrderStatus.newOrder);

  bool get isOpen => this != delivered && this != cancelled;
}

class OrderItem {
  const OrderItem({
    required this.id,
    this.variantId,
    this.productId,
    required this.name,
    this.nameHi,
    required this.label,
    required this.unit,
    required this.isLoose,
    required this.qty,
    required this.mrp,
    required this.price,
    required this.lineMrp,
    required this.discount,
    required this.lineTotal,
    this.freeQty = 0,
    this.offer,
    this.unavailable = false,
  });

  final String id;
  final String? variantId, productId;
  final String name;
  final String? nameHi;
  final String label;
  final SaleUnit unit;
  final bool isLoose;
  final double qty;
  final Paise mrp, price, lineMrp, discount, lineTotal;
  final double freeQty;
  final String? offer;
  final bool unavailable;

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
    id: j['id'] as String,
    variantId: j['variant_id'] as String?,
    productId: j['product_id'] as String?,
    name: j['name'] as String,
    nameHi: j['name_hi'] as String?,
    label: j['label'] as String,
    unit: SaleUnit.parse(j['unit'] as String?),
    isLoose: j['is_loose'] as bool? ?? false,
    qty: _qty(j['qty']),
    mrp: paiseFromJson(j['mrp']),
    price: paiseFromJson(j['price']),
    lineMrp: paiseFromJson(j['line_mrp']),
    discount: paiseFromJson(j['discount']),
    lineTotal: paiseFromJson(j['line_total']),
    freeQty: _qty(j['free_qty']),
    offer: j['offer'] as String?,
    unavailable: j['status'] == 'unavailable',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'variant_id': variantId,
    'product_id': productId,
    'name': name,
    'name_hi': nameHi,
    'label': label,
    'unit': unit.code,
    'is_loose': isLoose,
    'qty': qty,
    'mrp': paiseToJson(mrp),
    'price': paiseToJson(price),
    'line_mrp': paiseToJson(lineMrp),
    'discount': paiseToJson(discount),
    'line_total': paiseToJson(lineTotal),
    'free_qty': freeQty,
    'offer': offer,
    'status': unavailable ? 'unavailable' : 'ok',
  };
}

class OrderEvent {
  const OrderEvent({required this.status, this.note, required this.at});
  final String status;
  final String? note;
  final DateTime at;

  factory OrderEvent.fromJson(Map<String, dynamic> j) =>
      OrderEvent(status: j['status'] as String, note: j['note'] as String?, at: _date(j['at']) ?? DateTime.now());

  Map<String, dynamic> toJson() => {'status': status, 'note': note, 'at': at.toUtc().toIso8601String()};
}

class Order {
  const Order({
    required this.id,
    required this.orderNo,
    this.customerId,
    this.customerName,
    this.customerPhone,
    required this.status,
    required this.fulfilment,
    this.address,
    this.slotDate,
    this.slot,
    required this.subtotalMrp,
    required this.itemsTotal,
    this.itemDiscount = 0,
    this.cartDiscount = 0,
    this.cartOffer,
    this.couponCode,
    this.couponDiscount = 0,
    this.deliveryCharge = 0,
    required this.total,
    this.savings = 0,
    required this.paymentMethod,
    this.paymentStatus = 'pending',
    this.note,
    this.cancelReason,
    this.cancelledBy,
    required this.createdAt,
    this.items = const [],
    this.events = const [],
  });

  final String id;
  final int orderNo;
  final String? customerId, customerName, customerPhone;
  final OrderStatus status;
  final Fulfilment fulfilment;
  final Address? address;
  final DateTime? slotDate;
  final String? slot;
  final Paise subtotalMrp, itemsTotal, itemDiscount, cartDiscount;
  final String? cartOffer, couponCode;
  final Paise couponDiscount, deliveryCharge, total, savings;
  final String paymentMethod, paymentStatus;
  final String? note, cancelReason, cancelledBy;
  final DateTime createdAt;
  final List<OrderItem> items;
  final List<OrderEvent> events;

  List<OrderItem> get okItems => items.where((i) => !i.unavailable).toList();

  factory Order.fromJson(Map<String, dynamic> j) => Order(
    id: j['id'] as String,
    orderNo: (j['order_no'] as num).toInt(),
    customerId: j['customer_id'] as String?,
    customerName: j['customer_name'] as String?,
    customerPhone: j['customer_phone'] as String?,
    status: OrderStatus.parse(j['status'] as String?),
    fulfilment: j['fulfilment'] == 'pickup' ? Fulfilment.pickup : Fulfilment.delivery,
    address: j['address'] is Map ? Address.fromJson((j['address'] as Map).cast()) : null,
    slotDate: j['slot_date'] == null ? null : DateTime.tryParse(j['slot_date'] as String),
    slot: j['slot'] as String?,
    subtotalMrp: paiseFromJson(j['subtotal_mrp']),
    itemsTotal: paiseFromJson(j['items_total']),
    itemDiscount: paiseFromJson(j['item_discount']),
    cartDiscount: paiseFromJson(j['cart_discount']),
    cartOffer: j['cart_offer'] as String?,
    couponCode: j['coupon_code'] as String?,
    couponDiscount: paiseFromJson(j['coupon_discount']),
    deliveryCharge: paiseFromJson(j['delivery_charge']),
    total: paiseFromJson(j['total']),
    savings: paiseFromJson(j['savings']),
    paymentMethod: j['payment_method'] as String? ?? 'cod',
    paymentStatus: j['payment_status'] as String? ?? 'pending',
    note: j['note'] as String?,
    cancelReason: j['cancel_reason'] as String?,
    cancelledBy: j['cancelled_by'] as String?,
    createdAt: _date(j['created_at']) ?? DateTime.now(),
    items: ((j['order_items'] ?? j['items']) as List? ?? const [])
        .map((i) => OrderItem.fromJson((i as Map).cast()))
        .toList(),
    events:
        ((j['order_events'] ?? j['events']) as List? ?? const [])
            .map((e) => OrderEvent.fromJson((e as Map).cast()))
            .toList()
          ..sort((a, b) => a.at.compareTo(b.at)),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'order_no': orderNo,
    'customer_id': customerId,
    'customer_name': customerName,
    'customer_phone': customerPhone,
    'status': status.code,
    'fulfilment': fulfilment.name,
    'address': address?.toJson(),
    'slot_date': slotDate?.toIso8601String().substring(0, 10),
    'slot': slot,
    'subtotal_mrp': paiseToJson(subtotalMrp),
    'items_total': paiseToJson(itemsTotal),
    'item_discount': paiseToJson(itemDiscount),
    'cart_discount': paiseToJson(cartDiscount),
    'cart_offer': cartOffer,
    'coupon_code': couponCode,
    'coupon_discount': paiseToJson(couponDiscount),
    'delivery_charge': paiseToJson(deliveryCharge),
    'total': paiseToJson(total),
    'savings': paiseToJson(savings),
    'payment_method': paymentMethod,
    'payment_status': paymentStatus,
    'note': note,
    'cancel_reason': cancelReason,
    'cancelled_by': cancelledBy,
    'created_at': createdAt.toUtc().toIso8601String(),
    'items': items.map((i) => i.toJson()).toList(),
    'events': events.map((e) => e.toJson()).toList(),
  };
}
