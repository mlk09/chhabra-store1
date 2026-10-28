import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../data/models/order.dart';
import 'i18n.dart';
import 'money.dart';
import 'theme.dart';
import 'widgets/common.dart';

String statusText(BuildContext context, String code, {Fulfilment? fulfilment}) => switch (code) {
  'new' => context.tr('Order placed', 'ऑर्डर मिला'),
  'accepted' => context.tr('Accepted by shop', 'दुकान ने स्वीकार किया'),
  'packed' => context.tr('Packed', 'पैक हो गया'),
  'out_for_delivery' => context.tr('Out for delivery', 'डिलीवरी के लिए निकला'),
  'ready_for_pickup' => context.tr('Ready for pickup', 'पिकअप के लिए तैयार'),
  'delivered' =>
    fulfilment == Fulfilment.pickup ? context.tr('Picked up', 'ले लिया गया') : context.tr('Delivered', 'डिलीवर हो गया'),
  'cancelled' => context.tr('Cancelled', 'कैंसिल'),
  'item_unavailable' => context.tr('Item not available', 'सामान उपलब्ध नहीं'),
  _ => code,
};

/// Button text for the shop moving an order to [s].
String actionText(BuildContext context, OrderStatus s) => switch (s) {
  OrderStatus.accepted => context.tr('Accept order', 'ऑर्डर स्वीकार करें'),
  OrderStatus.packed => context.tr('Mark packed', 'पैक हो गया'),
  OrderStatus.outForDelivery => context.tr('Out for delivery', 'डिलीवरी पर भेजें'),
  OrderStatus.readyForPickup => context.tr('Ready for pickup', 'पिकअप के लिए तैयार'),
  OrderStatus.delivered => context.tr('Mark delivered', 'डिलीवर हो गया'),
  OrderStatus.cancelled => context.tr('Cancel order', 'ऑर्डर कैंसिल करें'),
  OrderStatus.newOrder => '',
};

Color statusColor(OrderStatus s) => switch (s) {
  OrderStatus.newOrder => Brand.saffron,
  OrderStatus.cancelled => Brand.red,
  OrderStatus.delivered => const Color(0xFF7C8A83),
  _ => Brand.green,
};

String paymentText(BuildContext context, String method) => switch (method) {
  'cod' => context.tr('Cash / pay on delivery', 'कैश / डिलीवरी पर भुगतान'),
  'upi_direct' => 'UPI',
  'gateway' => context.tr('Paid online', 'ऑनलाइन भुगतान'),
  _ => method,
};

String couponErrorText(BuildContext context, String code, {Paise? minOrder}) => switch (code) {
  'invalid' => context.tr('This coupon code is not valid.', 'यह कूपन कोड सही नहीं है।'),
  'expired' => context.tr('This coupon has expired.', 'यह कूपन ख़त्म हो चुका है।'),
  'not_started' => context.tr('This coupon is not active yet.', 'यह कूपन अभी शुरू नहीं हुआ।'),
  'used_up' => context.tr('This coupon has been fully used.', 'यह कूपन पूरा इस्तेमाल हो चुका है।'),
  'already_used' => context.tr('You have already used this coupon.', 'आप यह कूपन पहले इस्तेमाल कर चुके हैं।'),
  'login_required' => context.tr('Log in to use a coupon.', 'कूपन के लिए लॉग इन करें।'),
  'min_order' => context.tr(
    'Add items worth ${formatMoney(minOrder ?? 0)} to use this coupon.',
    'यह कूपन ${formatMoney(minOrder ?? 0)} की ख़रीद पर लगेगा।',
  ),
  _ => context.tr('This coupon cannot be used.', 'यह कूपन नहीं लग सकता।'),
};

/// Friendly text for errors from placing/changing orders.
String orderErrorText(BuildContext context, Object e) {
  if (e is! AppException || e.code == null) return errorText(context, e);
  final code = e.code!;
  if (code.startsWith('coupon_')) return couponErrorText(context, code.substring(7));
  return switch (code) {
    'login_required' => context.tr('Please log in to order.', 'ऑर्डर के लिए लॉग इन करें।'),
    'shop_closed' => context.tr('The shop is not taking orders right now.', 'दुकान अभी ऑर्डर नहीं ले रही है।'),
    'bad_slot' => context.tr(
      'That time slot is no longer available. Please pick another.',
      'यह समय अब उपलब्ध नहीं। दूसरा चुनें।',
    ),
    'address_required' => context.tr('Please choose a delivery address.', 'डिलीवरी का पता चुनें।'),
    'outside_area' => context.tr(
      'Sorry, we do not deliver to pincode ${e.data['pincode'] ?? ''} yet. You can choose pickup.',
      'माफ़ कीजिए, पिनकोड ${e.data['pincode'] ?? ''} पर अभी डिलीवरी नहीं है। पिकअप चुन सकते हैं।',
    ),
    'items_changed' => context.tr(
      'Some items just went out of stock. Please check your cart.',
      'कुछ सामान अभी स्टॉक से बाहर हुआ। कार्ट जाँचें।',
    ),
    'below_min_order' => context.tr(
      'Minimum order for delivery is ${formatMoney(paiseFromJson(e.data['min_order']))}.',
      'डिलीवरी के लिए कम से कम ${formatMoney(paiseFromJson(e.data['min_order']))} का ऑर्डर चाहिए।',
    ),
    'price_changed' => context.tr(
      'Prices changed just now. Please check the new total and place the order again.',
      'अभी रेट बदले हैं। नया टोटल देखकर फिर ऑर्डर करें।',
    ),
    'rate_limited' => context.tr('Too many tries. Please wait a few minutes.', 'बहुत बार कोशिश हुई। कुछ मिनट रुकें।'),
    'payment_off' ||
    'fulfilment_off' => context.tr('This option is switched off by the shop.', 'यह विकल्प दुकान ने बंद किया है।'),
    'bad_status' => context.tr('This step is not possible now.', 'यह कदम अभी संभव नहीं।'),
    'last_item' => context.tr(
      'This is the last item — cancel the order instead.',
      'यह आख़िरी सामान है — ऑर्डर कैंसिल करें।',
    ),
    'forbidden' => context.tr('You cannot change this order.', 'आप यह ऑर्डर नहीं बदल सकते।'),
    _ => context.pick(e.message, e.messageHi),
  };
}
