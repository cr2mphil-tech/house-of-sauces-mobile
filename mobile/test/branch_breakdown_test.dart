import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:house_of_sauces/app_state.dart';
import 'package:house_of_sauces/models.dart';
import 'package:house_of_sauces/screens.dart';
import 'package:provider/provider.dart';

const _branchId = '00000000-0000-4000-8000-000000000002';

class _BranchBreakdownState extends AppState {
  String? requestedSalesBranchId;
  String? requestedExpensesBranchId;

  _BranchBreakdownState() {
    user = const AppUser(
      id: '00000000-0000-4000-8000-000000000010',
      email: 'owner@example.com',
      role: 'owner',
    );
    restoring = false;
  }

  @override
  Future<List<Branch>> branches() async => const [
        Branch(id: _branchId, name: 'North Branch'),
      ];

  @override
  Future<Map<String, dynamic>> summary({
    String? from,
    String? to,
    String? paymentMode,
    String? orderType,
    String? category,
  }) async =>
      {
        'revenue': 1500,
        'cash_revenue': 1500,
        'bank_transfer_revenue': 0,
        'delivery_revenue': 0,
        'expenses': 300,
        'pending_count': 1,
        'net_profit': 1200,
        'order_count': 1,
      };

  @override
  Future<List<Map<String, dynamic>>> branchSummaries({
    String? from,
    String? to,
    String? branchId,
    String? paymentMode,
    String? orderType,
    String? category,
  }) async =>
      [
        {
          'branch_id': _branchId,
          'branch_name': 'North Branch',
          'revenue': 1500,
          'cash_revenue': 1500,
          'bank_transfer_revenue': 0,
          'delivery_revenue': 0,
          'expenses': 300,
          'pending_count': 1,
          'net_profit': 1200,
        },
      ];

  @override
  Future<List<MenuItem>> menu() async => const [];

  @override
  Future<List<Sale>> sales({
    String? from,
    String? to,
    String? menuSizeId,
    String? branchId,
    String? paymentMode,
    String? orderType,
    String? category,
  }) async {
    requestedSalesBranchId = branchId;
    return [
      Sale(
        id: 'sale-1',
        pizzaName: 'North Branch Pizza',
        category: 'Pizza',
        sizeName: 'Large',
        quantity: 1,
        unitPrice: 1500,
        deliveryFee: 0,
        totalAmount: 1500,
        orderType: 'pickup',
        paymentMode: 'cash',
        createdAt: DateTime(2026, 11, 8),
        branchName: 'North Branch',
      ),
      Sale(
        id: 'personal-use-1',
        pizzaName: 'Personal Pizza',
        category: 'Pizza',
        sizeName: 'Small',
        quantity: 1,
        unitPrice: 500,
        deliveryFee: 0,
        totalAmount: 500,
        orderType: 'pickup',
        paymentMode: 'personal_use',
        createdAt: DateTime(2026, 11, 8),
        branchName: 'North Branch',
      ),
    ];
  }

  @override
  Future<List<Expense>> expenses({
    String? from,
    String? to,
    String? branchId,
  }) async {
    requestedExpensesBranchId = branchId;
    return [
      Expense(
        id: 'expense-1',
        financialHead: 'Utilities',
        description: 'Pending electricity bill',
        amount: 300,
        status: 'pending',
        createdAt: DateTime(2026, 11, 8),
        branchName: 'North Branch',
      ),
    ];
  }
}

void main() {
  testWidgets(
    'branch breakup opens records for that branch including pending expenses',
    (tester) async {
      final state = _BranchBreakdownState();
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: const MaterialApp(
            home: Scaffold(body: DashboardScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Overall branch-wise breakup'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final branchCard = find.text(
        'Tap to open this branch’s sales and expense records',
      );
      await tester.ensureVisible(branchCard);
      await tester.tap(branchCard);
      await tester.pumpAndSettle();

      expect(find.text('North Branch breakdown'), findsOneWidget);
      expect(find.text('Gross revenue'), findsOneWidget);
      expect(
          find.text('Personal use · not included in revenue'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('North Branch Pizza · Large × 1'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('North Branch Pizza · Large × 1'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Utilities · pending'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Utilities · pending'), findsOneWidget);
      expect(state.requestedSalesBranchId, _branchId);
      expect(state.requestedExpensesBranchId, _branchId);
    },
  );
}
