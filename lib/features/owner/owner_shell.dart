import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/alerts.dart';
import '../../core/i18n.dart';
import '../../core/order_state.dart';
import '../orders/order_lists.dart';

/// Shopkeeper tabs (side rail on wide screens). Rings for new orders on every tab.
class OwnerShell extends ConsumerStatefulWidget {
  const OwnerShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  ConsumerState<OwnerShell> createState() => _OwnerShellState();
}

class _OwnerShellState extends ConsumerState<OwnerShell> {
  @override
  void initState() {
    super.initState();
    Alerts.init();
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    final fresh = ref.watch(newOrderCountProvider);
    Widget ordersIcon(IconData i) => Badge(isLabelVisible: fresh > 0, label: Text('$fresh'), child: Icon(i));
    final destinations = [
      (
        const Icon(Icons.space_dashboard_outlined),
        const Icon(Icons.space_dashboard_rounded),
        context.tr('Home', 'होम'),
      ),
      (ordersIcon(Icons.receipt_long_outlined), ordersIcon(Icons.receipt_long_rounded), context.tr('Orders', 'ऑर्डर')),
      (const Icon(Icons.inventory_2_outlined), const Icon(Icons.inventory_2_rounded), context.tr('Products', 'सामान')),
      (const Icon(Icons.menu_rounded), const Icon(Icons.menu_open_rounded), context.tr('More', 'और')),
    ];
    void go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

    final Widget page;
    if (MediaQuery.sizeOf(context).width >= 900) {
      page = Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: go,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(icon: d.$1, selectedIcon: d.$2, label: Text(d.$3)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: shell),
          ],
        ),
      );
    } else {
      page = Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: go,
          destinations: [
            for (final d in destinations) NavigationDestination(icon: d.$1, selectedIcon: d.$2, label: d.$3),
          ],
        ),
      );
    }
    return OrderAlerts(child: page);
  }
}
