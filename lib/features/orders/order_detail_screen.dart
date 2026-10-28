import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/order_state.dart';
import '../../core/order_text.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../core/widgets/common.dart';
import '../../data/models/member.dart';
import '../../data/models/order.dart';
import '../../domain/order_flow.dart';
import '../../domain/slots.dart';

/// One order. Customers see tracking + cancel/reorder; the shop sees the
/// customer, item "not available" and the next status buttons. Updates live.
class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId, this.shopView = false, this.justPlaced = false});
  final String orderId;
  final bool shopView;
  final bool justPlaced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(orderProvider(orderId));
    final session = ref.watch(sessionProvider).value;
    final canManage = shopView && (session?.can(Perm.orders) ?? false);
    AppBar bar() => AppBar(title: Text(context.tr('Order', 'ऑर्डर')));
    return async.when(
      loading: () => Scaffold(appBar: bar(), body: const LoadingView()),
      error: (e, _) => Scaffold(
        appBar: bar(),
        body: ErrorView(error: e, onRetry: () => ref.invalidate(orderProvider(orderId))),
      ),
      data: (o) => _Body(order: o, shopView: shopView, canManage: canManage, justPlaced: justPlaced),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.order, required this.shopView, required this.canManage, required this.justPlaced});
  final Order order;
  final bool shopView;
  final bool canManage;
  final bool justPlaced;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && done != null) showSnack(context, done);
    } catch (e) {
      if (mounted) showSnack(context, orderErrorText(context, e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(OrderStatus s) async {
    String? note;
    if (s == OrderStatus.cancelled) {
      note = await _askReason();
      if (note == null) return;
    }
    if (!mounted) return;
    await _run(
      () => ref.read(backendProvider).setOrderStatus(widget.order.id, s, note: note),
      done: statusText(context, s.code, fulfilment: widget.order.fulfilment),
    );
  }

  Future<String?> _askReason() async {
    final c = TextEditingController();
    final reasons = widget.shopView
        ? [
            context.tr('Items out of stock', 'सामान स्टॉक में नहीं'),
            context.tr('Cannot deliver now', 'अभी डिलीवरी नहीं हो सकती'),
            context.tr('Customer asked', 'ग्राहक ने कहा'),
          ]
        : [
            context.tr('Ordered by mistake', 'ग़लती से ऑर्डर हुआ'),
            context.tr('Want to change items', 'सामान बदलना है'),
            context.tr('Need it at another time', 'दूसरे समय चाहिए'),
          ];
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('Cancel this order?', 'यह ऑर्डर कैंसिल करें?')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final r in reasons) ActionChip(label: Text(r), onPressed: () => c.text = r)],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: c,
              maxLength: 200,
              decoration: InputDecoration(labelText: ctx.tr('Reason', 'कारण')),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('Keep order', 'ऑर्डर रखें'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.red),
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: Text(ctx.tr('Cancel order', 'कैंसिल करें')),
          ),
        ],
      ),
    );
    c.dispose();
    return r;
  }

  void _reorder() {
    final catalog = ref.read(catalogProvider).value;
    final items = <String, double>{};
    var missing = 0;
    for (final i in widget.order.okItems) {
      final hit = i.variantId == null ? null : catalog?.variant(i.variantId!);
      if (hit == null || !hit.$1.isActive || !hit.$2.isActive || !hit.$2.inStock) {
        missing++;
        continue;
      }
      items[i.variantId!] = i.qty;
    }
    final cart = ref.read(cartProvider.notifier);
    cart.replaceWith({...ref.read(cartProvider), ...items});
    if (missing > 0) {
      showSnack(context, context.tr('$missing items are not available now', '$missing सामान अभी उपलब्ध नहीं'));
    }
    context.push('/cart');
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final t = Theme.of(context);
    final shop = ref.watch(catalogProvider).value?.shop;
    final next = widget.canManage ? nextStatuses(o) : const <OrderStatus>[];
    final forward = next.where((s) => s != OrderStatus.cancelled).toList();
    final canItemUnavailable =
        widget.canManage && const {OrderStatus.newOrder, OrderStatus.accepted, OrderStatus.packed}.contains(o.status);

    final actions = _actions(next, forward);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Order #${o.orderNo}', 'ऑर्डर #${o.orderNo}'))),
      bottomNavigationBar: actions,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (widget.justPlaced)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Brand.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Brand.green, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.tr(
                        'Order placed! The shop will confirm it soon.',
                        'ऑर्डर हो गया! दुकान जल्द ही कन्फ़र्म करेगी।',
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          _StatusHeader(order: o),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        o.fulfilment == Fulfilment.delivery ? Icons.delivery_dining_rounded : Icons.storefront_rounded,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          o.fulfilment == Fulfilment.delivery
                              ? context.tr('Home delivery', 'होम डिलीवरी')
                              : context.tr('Pickup from shop', 'दुकान से पिकअप'),
                          style: t.textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  if (o.slotDate != null && o.slot != null) ...[
                    const SizedBox(height: 4),
                    Text('${DateFormat('EEE, d MMM').format(o.slotDate!)} · ${prettySlot(o.slot!)}'),
                  ],
                  if (o.address != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${o.address!.name} · ${o.address!.phone}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(o.address!.oneLine),
                  ] else if (widget.shopView && o.customerName != null) ...[
                    const SizedBox(height: 8),
                    Text([o.customerName, o.customerPhone].whereType<String>().join(' · ')),
                  ],
                  if (o.note != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      context.tr('Note: ${o.note}', 'नोट: ${o.note}'),
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    '${paymentText(context, o.paymentMethod)} · ${o.paymentStatus == 'paid' ? context.tr('Paid', 'भुगतान हो गया') : context.tr('Payment pending', 'भुगतान बाकी')}',
                    style: TextStyle(
                      color: o.paymentStatus == 'paid' ? Brand.green : Brand.saffronDeep,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (widget.shopView || shop?.phone != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (widget.shopView && (o.address?.phone ?? o.customerPhone) != null) ...[
                          OutlinedButton.icon(
                            onPressed: () => launchUrl(Uri.parse('tel:${o.address?.phone ?? o.customerPhone}')),
                            icon: const Icon(Icons.call_outlined),
                            label: Text(context.tr('Call', 'कॉल')),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => launchUrl(
                              Uri.parse(
                                'https://wa.me/91${(o.address?.phone ?? o.customerPhone)!.replaceAll(RegExp(r'^\+?91'), '')}',
                              ),
                              mode: LaunchMode.externalApplication,
                            ),
                            icon: const Icon(Icons.chat_outlined),
                            label: const Text('WhatsApp'),
                          ),
                        ] else if (!widget.shopView && shop?.phone != null)
                          OutlinedButton.icon(
                            onPressed: () => launchUrl(Uri.parse('tel:${shop!.phone}')),
                            icon: const Icon(Icons.call_outlined),
                            label: Text(context.tr('Call shop', 'दुकान को कॉल')),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          SectionTitle(context.tr('${o.items.length} items', '${o.items.length} सामान')),
          for (final i in o.items)
            _ItemRow(
              item: i,
              onUnavailable: canItemUnavailable && !i.unavailable
                  ? () => _run(
                      () => ref.read(backendProvider).markItemUnavailable(i.id),
                      done: context.tr('Marked not available — bill reduced', 'उपलब्ध नहीं किया — बिल कम हुआ'),
                    )
                  : null,
            ),
          const SizedBox(height: 8),
          _OrderBill(order: o),
          if (o.cancelReason != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                context.tr('Cancel reason: ${o.cancelReason}', 'कैंसिल का कारण: ${o.cancelReason}'),
                style: const TextStyle(color: Brand.red),
              ),
            ),
          SectionTitle(context.tr('Timeline', 'समय-रेखा')),
          for (final e in o.events.reversed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.circle, size: 10),
              title: Text(
                statusText(context, e.status, fulfilment: o.fulfilment) + (e.note == null ? '' : ' · ${e.note}'),
              ),
              trailing: Text(DateFormat('d MMM, h:mm a').format(e.at)),
            ),
          if (!widget.shopView && o.status == OrderStatus.delivered ||
              !widget.shopView && o.status == OrderStatus.cancelled)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                onPressed: _reorder,
                icon: const Icon(Icons.replay_rounded),
                label: Text(context.tr('Order again', 'फिर से मँगाएँ')),
              ),
            ),
        ],
      ),
    );
  }

  Widget? _actions(List<OrderStatus> next, List<OrderStatus> forward) {
    final o = widget.order;
    final customerCancel = !widget.shopView && o.status == OrderStatus.newOrder;
    if (!customerCancel && next.isEmpty) return null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            if (customerCancel)
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Brand.red),
                  onPressed: _busy ? null : () => _setStatus(OrderStatus.cancelled),
                  child: Text(context.tr('Cancel order', 'ऑर्डर कैंसिल करें')),
                ),
              ),
            if (next.contains(OrderStatus.cancelled)) ...[
              IconButton.outlined(
                tooltip: context.tr('Cancel order', 'ऑर्डर कैंसिल करें'),
                color: Brand.red,
                onPressed: _busy ? null : () => _setStatus(OrderStatus.cancelled),
                icon: const Icon(Icons.close_rounded),
              ),
              const SizedBox(width: 10),
            ],
            for (final s in forward)
              Expanded(
                child: FilledButton(onPressed: _busy ? null : () => _setStatus(s), child: Text(actionText(context, s))),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final steps = [
      OrderStatus.newOrder,
      OrderStatus.accepted,
      OrderStatus.packed,
      o.fulfilment == Fulfilment.delivery ? OrderStatus.outForDelivery : OrderStatus.readyForPickup,
      OrderStatus.delivered,
    ];
    final reached = o.status == OrderStatus.cancelled ? -1 : steps.indexOf(o.status);
    final color = statusColor(o.status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Pill(statusText(context, o.status.code, fulfilment: o.fulfilment), color: color, filled: true),
                const Spacer(),
                Text(DateFormat('d MMM, h:mm a').format(o.createdAt), style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            if (o.status != OrderStatus.cancelled) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  for (var i = 0; i < steps.length; i++) ...[
                    Icon(
                      i <= reached ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                      size: 22,
                      color: i <= reached ? Brand.green : Theme.of(context).colorScheme.outline,
                    ),
                    if (i < steps.length - 1)
                      Expanded(
                        child: Container(
                          height: 3,
                          color: i < reached ? Brand.green : Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                reached + 1 < steps.length
                    ? context.tr(
                        'Next: ${statusText(context, steps[reached + 1].code, fulfilment: o.fulfilment)}',
                        'अगला: ${statusText(context, steps[reached + 1].code, fulfilment: o.fulfilment)}',
                      )
                    : context.tr('Completed', 'पूरा हुआ'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, this.onUnavailable});
  final OrderItem item;
  final VoidCallback? onUnavailable;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final i = item;
    final style = i.unavailable
        ? TextStyle(decoration: TextDecoration.lineThrough, color: t.colorScheme.outline)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${context.pick(i.name, i.nameHi)} · ${i.label}', style: style ?? t.textTheme.bodyLarge),
                Text(
                  '${i.isLoose ? formatQty(i.qty, i.unit) : '${formatQty(i.qty, SaleUnit.pc)} ×'} ${formatMoney(i.price)}${i.isLoose ? '/${i.unit.code}' : ''}',
                  style: style ?? t.textTheme.bodySmall,
                ),
                if (i.offer != null && !i.unavailable)
                  Text(
                    i.offer!,
                    style: const TextStyle(color: Brand.green, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                if (i.unavailable)
                  Text(
                    context.tr('Not available — not charged', 'उपलब्ध नहीं — पैसे नहीं लगे'),
                    style: const TextStyle(color: Brand.red, fontSize: 13),
                  ),
              ],
            ),
          ),
          Text(formatMoney(i.lineTotal), style: (style ?? const TextStyle()).copyWith(fontWeight: FontWeight.w700)),
          if (onUnavailable != null)
            PopupMenuButton<int>(
              tooltip: context.tr('More', 'और'),
              onSelected: (_) => onUnavailable!(),
              itemBuilder: (ctx) => [PopupMenuItem(value: 1, child: Text(ctx.tr('Not available', 'उपलब्ध नहीं')))],
            ),
        ],
      ),
    );
  }
}

class _OrderBill extends StatelessWidget {
  const _OrderBill({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    Widget row(String a, String b, {Color? color, bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              a,
              style: TextStyle(color: color, fontWeight: bold ? FontWeight.w800 : null),
            ),
          ),
          Text(
            b,
            style: TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              fontSize: bold ? 18 : null,
            ),
          ),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            row(context.tr('Items (MRP)', 'सामान (MRP)'), formatMoney(o.subtotalMrp)),
            if (o.subtotalMrp > o.itemsTotal)
              row(
                context.tr('Discount on MRP & offers', 'MRP और ऑफ़र छूट'),
                '− ${formatMoney(o.subtotalMrp - o.itemsTotal)}',
                color: Brand.green,
              ),
            if (o.cartDiscount > 0)
              row(
                o.cartOffer ?? context.tr('Cart offer', 'कार्ट ऑफ़र'),
                '− ${formatMoney(o.cartDiscount)}',
                color: Brand.green,
              ),
            if (o.couponDiscount > 0)
              row(
                context.tr('Coupon ${o.couponCode ?? ''}', 'कूपन ${o.couponCode ?? ''}'),
                '− ${formatMoney(o.couponDiscount)}',
                color: Brand.green,
              ),
            row(
              context.tr('Delivery', 'डिलीवरी'),
              o.deliveryCharge > 0 ? formatMoney(o.deliveryCharge) : context.tr('FREE', 'फ़्री'),
            ),
            const Divider(height: 18),
            row(context.tr('Total', 'कुल'), formatMoney(o.total), bold: true),
            if (o.savings > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  context.tr('You saved ${formatMoney(o.savings)}', '${formatMoney(o.savings)} की बचत'),
                  style: const TextStyle(color: Brand.green, fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
