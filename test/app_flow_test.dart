import 'package:chhabra_store/app.dart';
import 'package:chhabra_store/core/app_state.dart';
import 'package:chhabra_store/data/local/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whole-app tests in Demo mode (tests run without Supabase, like a Demo-only build).
void main() {
  late LocalStore store;
  setUp(() => store = LocalStore.memory());

  // Use the real Mukta font so text sizes (and overflows) match a phone.
  setUpAll(() async {
    final loader = FontLoader('Mukta');
    for (final w in ['Regular', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Mukta-$w.ttf'));
    }
    await loader.load();
  });

  Future<void> pumpApp(WidgetTester tester, {Size size = const Size(400, 860)}) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bootstrapProvider.overrideWith((ref) async => store)],
        retry: (_, _) => null,
        child: const KiranaApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('first launch shows welcome with both demo options', (tester) async {
    await store.setPref('seenWelcome', null);
    await pumpApp(tester);
    expect(find.text('Demo: Customer'), findsOneWidget);
    expect(find.text('Demo: Shopkeeper'), findsOneWidget);
    expect(find.textContaining('Demo mode only'), findsOneWidget);
  });

  testWidgets('customer demo: browse, search in Hinglish, open product', (tester) async {
    await store.setPref('seenWelcome', null);
    await pumpApp(tester);
    await tester.tap(find.text('Demo: Customer'));
    await tester.pumpAndSettle();

    expect(find.text('Shop by category'), findsOneWidget);
    expect(find.textContaining('Demo shop'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.textContaining('Search "atta"'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'aloo');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Potato'), findsOneWidget);

    await tester.tap(find.text('Potato'));
    await tester.pumpAndSettle();
    expect(find.text('₹25/kg'), findsOneWidget);
    expect(find.textContaining('Sold loose by weight'), findsOneWidget);
  });

  testWidgets('Hindi toggle switches the interface language', (tester) async {
    await store.setPref('seenWelcome', null);
    await pumpApp(tester);
    await tester.tap(find.text('हिंदी'));
    await tester.pumpAndSettle();
    expect(find.text('डेमो: ग्राहक'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
  });

  testWidgets('shopkeeper demo: dashboard, add a product, it appears in the list', (tester) async {
    await store.setPref('seenWelcome', null);
    await pumpApp(tester);
    await tester.tap(find.text('Demo: Shopkeeper'));
    await tester.pumpAndSettle();
    expect(find.text('Shop dashboard'), findsOneWidget);
    expect(find.text('Low stock'), findsWidgets);

    await tester.tap(find.text('Add product').first);
    await tester.pumpAndSettle();
    expect(find.text('Name (English) *'), findsOneWidget);

    // Saving empty form shows validation instead of crashing.
    await tester.tap(find.text('Save product'));
    await tester.pumpAndSettle();
    expect(find.text('Name is required'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Name (English) *'), 'Kachi Ghani Test Oil');
    await tester.enterText(find.widgetWithText(TextFormField, 'Size *'), '1 L');
    await tester.enterText(find.widgetWithText(TextFormField, 'MRP'), '200');
    await tester.enterText(find.widgetWithText(TextFormField, 'Selling price *'), '250');
    await tester.tap(find.text('Save product'));
    await tester.pumpAndSettle();
    expect(find.text('More than MRP'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Selling price *'), '180');
    await tester.pumpAndSettle();
    expect(find.text('Customers see 10% OFF'), findsOneWidget);
    await tester.tap(find.text('Save product'));
    await tester.pumpAndSettle();
    expect(find.text('Saved ✓'), findsOneWidget);

    await tester.tap(find.text('Products'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'kachi ghani test');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Kachi Ghani Test Oil'), findsOneWidget);
  });

  testWidgets('large system font does not overflow the customer home', (tester) async {
    await store.setPref('seenWelcome', true);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, size: const Size(360, 740));
    expect(find.textContaining('Search "atta"'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('large system font: shopkeeper screens have no overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, size: const Size(360, 740));
    await tester.tap(find.text('Demo: Shopkeeper'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'dashboard');

    await tester.tap(find.text('Products'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'products list');

    await tester.tap(find.textContaining('Aashirvaad'));
    await tester.pumpAndSettle();
    expect(find.text('Edit product'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'product editor');
  });

  testWidgets('bulk photos screen opens; AI is off in demo with an explanation', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, size: const Size(360, 740));
    await tester.tap(find.text('Demo: Shopkeeper'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Products'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bulk photos'));
    await tester.pumpAndSettle();
    expect(find.text('Add many photos at once'), findsOneWidget);
    expect(find.text('Works in the real shop after setup'), findsOneWidget);
    expect(find.textContaining('Choose photos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('product editor offers "Fill from photo (AI)"', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Demo: Shopkeeper'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add product').first);
    await tester.pumpAndSettle();
    expect(find.text('Fill from photo (AI)'), findsOneWidget);
  });
}
