import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';

/// Bottom navigation for the shopkeeper side (side rail on wide screens).
class OwnerShell extends StatelessWidget {
  const OwnerShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final destinations = [
      (Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, context.tr('Home', 'होम')),
      (Icons.inventory_2_outlined, Icons.inventory_2_rounded, context.tr('Products', 'सामान')),
      (Icons.menu_rounded, Icons.menu_open_rounded, context.tr('More', 'और')),
    ];
    void go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

    if (MediaQuery.sizeOf(context).width >= 900) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: go,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: shell),
          ],
        ),
      );
    }
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: go,
        destinations: [
          for (final d in destinations) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
        ],
      ),
    );
  }
}
