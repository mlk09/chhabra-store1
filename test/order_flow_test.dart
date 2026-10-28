import 'package:chhabra_store/app.dart';
import 'package:chhabra_store/core/app_state.dart';
import 'package:chhabra_store/data/demo/demo_backend.dart';
import 'package:chhabra_store/data/local/local_store.dart';
import 'package:chhabra_store/data/models/order.dart';
import 'package:chhabra_store/features/orders/order_lists.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 2 end-to-end in Demo mode: cart → offers → checkout → order → shop side.
void main() {
  late LocalStore store;
  late List<String> alerts;

  setUpAll(() async {
    final loader = FontLoader('Mukta');
    for (final w in ['Regular', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Mukta-$w.ttf'));
    }
    await loader.load();
  });

  setUp(() {
    store = LocalStore.memory();
    DemoStore.reset();
    alerts = [];
  });

  Future<void> pumpApp(WidgetTester tester, {Size size = const Size(400, 860), double textScale = 1}) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    if (textScale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith((ref) async => store),
          orderAlertSinkProvider.overrideWithValue((no, title, body) => alerts.add(title)),
        ],
        retry: (_, _) => null,
        child: const KiranaApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 400)); // quote debounce
    await tester.pumpAndSettle();
  }

  Future<void> addBySearch(WidgetTester tester, String query, {int extra = 0}) async {
    await tester.tap(find.textContaining('Search "atta"'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), query);
    await settle(tester);
    await tester.tap(find.text('ADD').first);
    await settle(tester);
    for (var i = 0; i < extra; i++) {
      await tester.tap(find.byTooltip('More').first);
      await settle(tester);
    }
    await tester.pageBack();
    await tester.pumpAndSettle();
  }

  testWidgets('customer: cart with Buy-2-Get-1, coupon check, checkout, order placed', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Demo: Customer'));
    await tester.pumpAndSettle();

    await addBySearch(tester, 'parle', extra: 2); // 3 × Parle-G 250 g → 1 free
    await addBySearch(tester, 'aashirvaad'); // Atta 1 kg ₹62
    expect(find.textContaining('2 items'), findsOneWidget, reason: 'cart bar');

    await tester.tap(find.text('View cart'));
    await settle(tester);
    expect(find.textContaining('1 free'), findsOneWidget);
    expect(find.textContaining('You saved'), findsOneWidget);
    // 3×25 − 25 free + 62 = 112, delivery 20 → 132
    expect(find.text('₹132'), findsWidgets);

    // Coupon with a minimum the cart doesn't meet → friendly message, no discount.
    await tester.enterText(find.widgetWithText(TextField, 'Coupon code'), 'welcome50');
    await tester.tap(find.text('Apply'));
    await settle(tester);
    expect(find.textContaining('Add items worth ₹300'), findsOneWidget);
    await tester.tap(find.text('Remove').last);
    await settle(tester);

    await tester.tap(find.text('Checkout'));
    await settle(tester);
    expect(find.textContaining('Demo Customer'), findsWidgets, reason: 'saved address is pre-selected');
    expect(find.text('Place order · ₹132'), findsOneWidget);
    await tester.tap(find.text('Place order · ₹132'));
    await settle(tester);

    expect(find.textContaining('Order placed!'), findsOneWidget);
    expect(find.text('Order #3'), findsOneWidget, reason: 'two sample orders exist');
    expect(DemoStore.instance.orders.length, 3);
    final atta = DemoStore.instance.catalog.products.firstWhere((p) => p.name.startsWith('Aashirvaad'));
    expect(atta.variants.first.stock, 29, reason: 'stock went down');

    // Customer can still cancel a brand-new order → stock comes back.
    await tester.tap(find.text('Cancel order').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ordered by mistake'));
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel order'));
    await settle(tester);
    expect(DemoStore.instance.orders.last.status, OrderStatus.cancelled);
    final back = DemoStore.instance.catalog.products.firstWhere((p) => p.name.startsWith('Aashirvaad'));
    expect(back.variants.first.stock, 30);
  });

  testWidgets('below minimum order: checkout blocked for delivery, allowed for pickup', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Demo: Customer'));
    await tester.pumpAndSettle();
    await addBySearch(tester, 'tata salt'); // ₹28 < ₹100 minimum
    await tester.tap(find.text('View cart'));
    await settle(tester);
    expect(find.textContaining('Minimum order for delivery'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Checkout')).onPressed, isNull);
    await tester.tap(find.text('Pick up'));
    await settle(tester);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Checkout')).onPressed, isNotNull);
  });

  testWidgets('shopkeeper: new order rings, accept → pack → item unavailable → deliver', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Demo: Shopkeeper'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Today:'), findsWidgets);

    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test new order'));
    await settle(tester);
    expect(alerts, hasLength(1), reason: 'bell + notification for the new order');
    expect(find.textContaining('New order #3'), findsWidgets, reason: 'banner');
    expect(find.text('Sunita Sharma').hitTestable(), findsOneWidget);

    await tester.tap(find.text('Sunita Sharma').hitTestable());
    await settle(tester);
    await tester.tap(find.text('Accept order'));
    await settle(tester);
    expect(find.text('Accepted by shop'), findsWidgets);

    final before = DemoStore.instance.orders.last.total;
    await tester.tap(find.byTooltip('More').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not available'));
    await settle(tester);
    final after = DemoStore.instance.orders.last;
    expect(after.total, lessThan(before), reason: 'bill goes down');
    expect(after.items.where((i) => i.unavailable), hasLength(1));

    await tester.tap(find.text('Mark packed'));
    await settle(tester);
    await tester.tap(find.text('Out for delivery'));
    await settle(tester);
    await tester.tap(find.text('Mark delivered'));
    await settle(tester);
    expect(DemoStore.instance.orders.last.status, OrderStatus.delivered);
    expect(DemoStore.instance.orders.last.paymentStatus, 'paid');
  });

  testWidgets('owner creates an offer from the Offers screen', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Demo: Shopkeeper'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Offers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New offer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Title customers see *'), 'Atta 10% off');
    await tester.tap(find.text('Choose product *'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'aashirvaad');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aashirvaad Whole Wheat Atta').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Discount % *'), '10');
    await tester.tap(find.text('Save offer'));
    await tester.pumpAndSettle();
    expect(find.text('Atta 10% off'), findsOneWidget);
    expect(DemoStore.instance.catalog.offers.any((o) => o.title == 'Atta 10% off'), isTrue);
  });

  testWidgets('large font: cart, checkout and order screens do not overflow', (tester) async {
    await pumpApp(tester, size: const Size(360, 740), textScale: 1.6);
    await tester.tap(find.text('Demo: Customer'));
    await tester.pumpAndSettle();
    await addBySearch(tester, 'aashirvaad', extra: 1);
    expect(tester.takeException(), isNull, reason: 'product cards with ADD');
    await tester.tap(find.text('View cart'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'cart');
    await tester.tap(find.text('Checkout'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'checkout');
    await tester.tap(find.textContaining('Place order'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'order detail');
    await tester.tap(find.text('Orders'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'my orders');
  });
}
