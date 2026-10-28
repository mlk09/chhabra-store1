import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/alerts.dart';
import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/order_state.dart';
import '../../core/order_text.dart';
import '../../core/widgets/common.dart';
import '../../data/demo/demo_backend.dart';
import '../../data/models/order.dart';
import '../../domain/slots.dart';
import '../common/demo_banner.dart';

class OrderTile extends StatelessWidget {
  const OrderTile({super.key, required this.order, required this.onTap, this.shopView = false});
  final Order order;
  final VoidCallback onTap;
  final bool shopView;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final t = Theme.of(context);
    final slot = o.slotDate == null || o.slot == null
        ? null
        : '${DateFormat('d MMM').format(o.slotDate!)} · ${prettySlot(o.slot!)}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('#${o.orderNo}', style: t.textTheme.titleMedium),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      shopView
                          ? (o.customerName ?? context.tr('Customer', 'ग्राहक'))
                          : DateFormat('d MMM, h:mm a').format(o.createdAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodyLarge,
                    ),
                  ),
                  Text(formatMoney(o.total), style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Pill(
                    statusText(context, o.status.code, fulfilment: o.fulfilment),
                    color: statusColor(o.status),
                    filled: o.status == OrderStatus.newOrder,
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    o.fulfilment == Fulfilment.delivery ? Icons.delivery_dining_rounded : Icons.storefront_rounded,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(slot ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Customer: "My orders".
class MyOrdersScreen extends ConsumerWidget {
  const MyOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    final orders = ref.watch(myOrdersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('My orders', 'मेरे ऑर्डर'))),
      body: session == null || !session.isLoggedIn
          ? MessageView(
              icon: Icons.receipt_long_outlined,
              title: context.tr('Log in to see your orders', 'ऑर्डर देखने के लिए लॉग इन करें'),
              actionLabel: context.tr('Log in', 'लॉग इन'),
              onAction: () => context.push('/login'),
            )
          : orders.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(myOrdersProvider)),
              data: (list) => list.isEmpty
                  ? MessageView(
                      icon: Icons.receipt_long_outlined,
                      title: context.tr('No orders yet', 'अभी कोई ऑर्डर नहीं'),
                      actionLabel: context.tr('Start shopping', 'ख़रीदारी शुरू करें'),
                      onAction: () => context.go('/shop'),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const DemoBanner(),
                        for (final o in list) OrderTile(order: o, onTap: () => context.push('/orders/${o.id}')),
                      ],
                    ),
            ),
    );
  }
}

enum _ShopFilter { fresh, active, done, cancelled }

/// Shop: live order list with filters. New orders ring (see OrderAlerts).
class ShopOrdersScreen extends ConsumerStatefulWidget {
  const ShopOrdersScreen({super.key});
  @override
  ConsumerState<ShopOrdersScreen> createState() => _ShopOrdersScreenState();
}

class _ShopOrdersScreenState extends ConsumerState<ShopOrdersScreen> {
  _ShopFilter _filter = _ShopFilter.fresh;

  static bool _match(Order o, _ShopFilter f) => switch (f) {
    _ShopFilter.fresh => o.status == OrderStatus.newOrder,
    _ShopFilter.active => o.status.isOpen && o.status != OrderStatus.newOrder,
    _ShopFilter.done => o.status == OrderStatus.delivered,
    _ShopFilter.cancelled => o.status == OrderStatus.cancelled,
  };

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(shopOrdersProvider);
    final session = ref.watch(sessionProvider).value;
    final all = orders.value ?? const <Order>[];
    int count(_ShopFilter f) => all.where((o) => _match(o, f)).length;

    final today = DateTime.now();
    final todays = all.where((o) => o.status != OrderStatus.cancelled && DateUtils.isSameDay(o.createdAt, today));
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Orders', 'ऑर्डर')),
        actions: [
          if (session?.isDemo ?? false)
            TextButton.icon(
              onPressed: () {
                final backend = ref.read(backendProvider);
                if (backend is DemoBackend) backend.simulateNewOrder();
              },
              icon: const Icon(Icons.notifications_active_outlined),
              label: Text(context.tr('Test new order', 'नया ऑर्डर टेस्ट')),
            ),
        ],
      ),
      body: orders.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(shopOrdersProvider)),
        data: (_) {
          final list = all.where((o) => _match(o, _filter)).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  context.tr(
                    'Today: ${todays.length} orders · ${formatMoney(todays.fold(0, (s, o) => s + o.total))}',
                    'आज: ${todays.length} ऑर्डर · ${formatMoney(todays.fold(0, (s, o) => s + o.total))}',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final f in _ShopFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            '${switch (f) {
                              _ShopFilter.fresh => context.tr('New', 'नए'),
                              _ShopFilter.active => context.tr('In progress', 'चल रहे'),
                              _ShopFilter.done => context.tr('Delivered', 'डिलीवर'),
                              _ShopFilter.cancelled => context.tr('Cancelled', 'कैंसिल'),
                            }} (${count(f)})',
                          ),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? MessageView(
                        icon: Icons.inbox_outlined,
                        title: context.tr('Nothing here', 'यहाँ कुछ नहीं'),
                        message: _filter == _ShopFilter.fresh
                            ? context.tr(
                                'New orders appear here instantly, with a bell sound.',
                                'नए ऑर्डर यहाँ तुरंत आएँगे, घंटी के साथ।',
                              )
                            : null,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: list.length,
                        itemBuilder: (_, i) => OrderTile(
                          order: list[i],
                          shopView: true,
                          onTap: () => context.push('/owner/order/${list[i].id}'),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Wraps the shopkeeper screens: rings + shows a banner when a new order arrives.
class OrderAlerts extends ConsumerStatefulWidget {
  const OrderAlerts({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<OrderAlerts> createState() => _OrderAlertsState();
}

class _OrderAlertsState extends ConsumerState<OrderAlerts> {
  Set<String>? _known;

  @override
  Widget build(BuildContext context) {
    ref.listen(shopOrdersProvider, (prev, next) {
      final list = next.value;
      if (list == null) return;
      final ids = list.map((o) => o.id).toSet();
      final known = _known;
      _known = ids;
      if (known == null) return; // first load: don't ring for old orders
      final fresh = list.where((o) => !known.contains(o.id) && o.status == OrderStatus.newOrder).toList();
      for (final o in fresh) {
        final title = context.tr(
          'New order #${o.orderNo} · ${formatMoney(o.total)}',
          'नया ऑर्डर #${o.orderNo} · ${formatMoney(o.total)}',
        );
        final body = [o.customerName, o.slot == null ? null : prettySlot(o.slot!)].whereType<String>().join(' · ');
        onNewOrder(o.orderNo, title, body);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 8),
              content: Text(title),
              action: SnackBarAction(
                label: context.tr('View', 'देखें'),
                onPressed: () => context.push('/owner/order/${o.id}'),
              ),
            ),
          );
      }
    });
    return widget.child;
  }

  void onNewOrder(int no, String title, String body) => ref.read(orderAlertSinkProvider)(no, title, body);
}

/// Indirection so widget tests can count alerts without playing sounds.
final orderAlertSinkProvider = Provider<void Function(int, String, String)>(
  (ref) =>
      (no, title, body) => Alerts.newOrder(orderNo: no, title: title, body: body),
);
