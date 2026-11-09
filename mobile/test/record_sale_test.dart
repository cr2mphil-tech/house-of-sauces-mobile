import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:house_of_sauces/app_state.dart';
import 'package:house_of_sauces/models.dart';
import 'package:house_of_sauces/screens.dart';
import 'package:provider/provider.dart';

class _RecordSaleState extends AppState {
  _RecordSaleState() {
    user = const AppUser(
      id: 'admin-id',
      email: 'admin@example.com',
      role: 'branch_admin',
      branchId: 'branch-id',
    );
    restoring = false;
  }

  List<Map<String, dynamic>>? recordedItems;
  double? recordedDeliveryFee;
  String? recordedCustomerName;
  String? recordedCustomerPhone;
  String? recordedPaymentMode;

  @override
  Future<List<MenuItem>> menu() async => const [
        MenuItem(
          id: 'pizza',
          name: 'Chicken Tikka',
          category: 'Pizza',
          sizes: [
            MenuSize(id: 'pizza-large', name: 'Large', price: 1250),
          ],
        ),
        MenuItem(
          id: 'deal',
          name: 'Family Deal',
          category: 'Deals',
          sizes: [
            MenuSize(id: 'deal-regular', name: 'Regular', price: 1999),
          ],
        ),
      ];

  @override
  Future<void> recordSale({
    required List<Map<String, dynamic>> items,
    required String orderType,
    required String paymentMode,
    required double deliveryFee,
    String? customerName,
    String? customerPhone,
  }) async {
    recordedItems = items;
    recordedDeliveryFee = deliveryFee;
    recordedCustomerName = customerName;
    recordedCustomerPhone = customerPhone;
    recordedPaymentMode = paymentMode;
  }
}

void main() {
  testWidgets('records multiple delivery items with one customer and fee',
      (tester) async {
    final state = _RecordSaleState();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: RecordSaleScreen()),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> selectProduct(int index, String name) async {
      await tester
          .tap(find.byType(DropdownButtonFormField<MenuItem>).at(index));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    Future<void> selectSize(int index, String name) async {
      await tester
          .tap(find.byType(DropdownButtonFormField<MenuSize>).at(index));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    await selectProduct(0, 'Pizza · Chicken Tikka');
    await selectSize(0, 'Large · Rs 1,250');
    await tester.tap(find.text('Add more order items'));
    await tester.pumpAndSettle();
    await selectProduct(1, 'Deals · Family Deal');
    await selectSize(1, 'Regular · Rs 1,999');

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick-up'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delivery').last);
    await tester.pumpAndSettle();

    Finder input(String label) => find.ancestor(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is InputDecorator &&
                widget.decoration.labelText == label,
          ),
          matching: find.byType(TextFormField),
        );
    await tester.ensureVisible(input('Customer name'));
    await tester.enterText(input('Customer name'), 'Sam Customer');
    await tester.ensureVisible(input('Customer phone number'));
    await tester.enterText(input('Customer phone number'), '+923001234567');
    await tester.ensureVisible(input('Delivery charges'));
    await tester.enterText(input('Delivery charges'), '275');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personal use · excluded from sales'));
    await tester.pumpAndSettle();

    expect(find.text('Rs 3,524'), findsOneWidget);
    await tester.ensureVisible(find.text('Save personal-use record'));
    await tester.tap(find.text('Save personal-use record'));
    await tester.pumpAndSettle();

    expect(state.recordedItems, hasLength(2));
    expect(state.recordedDeliveryFee, 275);
    expect(state.recordedCustomerName, 'Sam Customer');
    expect(state.recordedCustomerPhone, '+923001234567');
    expect(state.recordedPaymentMode, 'personal_use');
  });
}
