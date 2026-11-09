import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:house_of_sauces/app_state.dart';
import 'package:house_of_sauces/models.dart';
import 'package:house_of_sauces/screens.dart';
import 'package:provider/provider.dart';

const _branchId = '00000000-0000-4000-8000-000000000001';
const _secondBranchId = '00000000-0000-4000-8000-000000000002';
const _thirdBranchId = '00000000-0000-4000-8000-000000000003';
const _saleId = '00000000-0000-4000-8000-000000000101';
const _expenseId = '00000000-0000-4000-8000-000000000201';
const _screenKey = ValueKey('preview-screen');

final _branches = [
  const Branch(id: _branchId, name: 'Main Branch', address: 'Central'),
  const Branch(id: _secondBranchId, name: 'North Branch', address: 'North'),
  const Branch(id: _thirdBranchId, name: 'South Branch', address: 'South'),
];

final _menu = [
  const MenuItem(
    id: 'item-tikka',
    name: 'Chicken Tikka',
    category: 'Regular Flavour Pizzas',
    description: 'Smoky chicken tikka with signature sauce',
    sizes: [
      MenuSize(id: 'size-small', name: 'Small', price: 650),
      MenuSize(id: 'size-large', name: 'Large', price: 1250),
    ],
  ),
  const MenuItem(
    id: 'item-deal',
    name: 'Family Deal',
    category: 'Deals',
    description: 'Two pizzas, fries and a drink',
    sizes: [MenuSize(id: 'size-deal', name: 'Regular', price: 1999)],
  ),
];

final _sales = [
  Sale(
    id: _saleId,
    pizzaName: 'Chicken Tikka',
    category: 'Regular Flavour Pizzas',
    productDescription: 'Smoky chicken tikka with signature sauce',
    sizeName: 'Large',
    quantity: 2,
    unitPrice: 1250,
    deliveryFee: 150,
    totalAmount: 2650,
    orderType: 'delivery',
    paymentMode: 'cash',
    createdAt: DateTime(2026, 11, 8, 18, 30),
    branchName: 'Main Branch',
  ),
];

final _expenses = [
  Expense(
    id: _expenseId,
    financialHead: 'Utilities',
    description: 'November electricity bill',
    amount: 4200,
    status: 'pending',
    createdAt: DateTime(2026, 11, 8, 17, 15),
    branchName: 'Main Branch',
  ),
  Expense(
    id: '00000000-0000-4000-8000-000000000202',
    financialHead: 'Packaging',
    description: 'Pizza boxes and delivery bags',
    amount: 1800,
    status: 'settled',
    settlementMode: 'bank_transfer',
    createdAt: DateTime(2026, 11, 7, 11),
    branchName: 'North Branch',
  ),
];

class _PreviewState extends AppState {
  _PreviewState({required bool owner}) {
    user = AppUser(
      id: '00000000-0000-4000-8000-000000000010',
      email: owner ? 'owner@example.com' : 'admin@example.com',
      role: owner ? 'owner' : 'branch_admin',
      branchId: owner ? null : _branchId,
    );
    selectedBranchId = owner ? null : _branchId;
    restoring = false;
  }

  @override
  Future<List<Branch>> branches() async => _branches;

  @override
  Future<Map<String, dynamic>> summary({
    String? from,
    String? to,
    String? paymentMode,
    String? orderType,
    String? category,
  }) async =>
      {
        'revenue': 28750,
        'cash_revenue': 16750,
        'bank_transfer_revenue': 12000,
        'expenses': 7600,
        'pending_count': 2,
        'net_profit': 21150,
        'order_count': 18,
      };

  @override
  Future<List<Map<String, dynamic>>> branchSummaries({
    String? from,
    String? to,
    String? branchId,
    String? paymentMode,
    String? orderType,
    String? category,
  }) async {
    final summaries = [
      {
        'branch_id': _branchId,
        'branch_name': 'Main Branch',
        'revenue': 14250,
        'cash_revenue': 8250,
        'bank_transfer_revenue': 6000,
        'expenses': 4200,
        'pending_count': 1,
        'net_profit': 10050,
      },
      {
        'branch_id': _secondBranchId,
        'branch_name': 'North Branch',
        'revenue': 9300,
        'cash_revenue': 5300,
        'bank_transfer_revenue': 4000,
        'expenses': 1800,
        'pending_count': 1,
        'net_profit': 7500,
      },
      {
        'branch_id': _thirdBranchId,
        'branch_name': 'South Branch',
        'revenue': 5200,
        'cash_revenue': 3200,
        'bank_transfer_revenue': 2000,
        'expenses': 1600,
        'pending_count': 0,
        'net_profit': 3600,
      },
    ];
    return branchId == null
        ? summaries
        : summaries.where((branch) => branch['branch_id'] == branchId).toList();
  }

  @override
  Future<List<Sale>> sales({
    String? from,
    String? to,
    String? menuSizeId,
    String? branchId,
    String? paymentMode,
    String? orderType,
    String? category,
  }) async =>
      _sales;

  @override
  Future<List<Expense>> expenses({
    String? from,
    String? to,
    String? branchId,
  }) async =>
      _expenses;

  @override
  Future<List<String>> expenseHeads() async =>
      ['Utilities', 'Packaging', 'Rent', 'Supplies'];

  @override
  Future<List<MenuItem>> menu() async => _menu;

  @override
  Future<List<Map<String, dynamic>>> hotSelling({
    String? category,
    String? size,
    String? from,
    String? to,
  }) async =>
      [
        {
          'pizza_name': 'Chicken Tikka',
          'category': 'Regular Flavour Pizzas',
          'size_name': 'Large',
          'branch_name': 'Main Branch',
          'quantity_sold': 26,
          'revenue': 32500,
        },
        {
          'pizza_name': 'Family Deal',
          'category': 'Deals',
          'size_name': 'Regular',
          'branch_name': 'North Branch',
          'quantity_sold': 18,
          'revenue': 35982,
        },
      ];

  @override
  Future<List<Map<String, dynamic>>> branchAdmins({String? branchId}) async => [
        {
          'id': '00000000-0000-4000-8000-000000000011',
          'email': 'manager@houseofsauces.example',
          'branch_id': branchId ?? _branchId,
          'branch_name': 'Main Branch',
        },
      ];

  @override
  Future<List<Map<String, dynamic>>> auditLog() async => [
        {
          'action': 'sale.recorded',
          'entity_type': 'sale',
          'entity_id': _saleId,
          'branch_name': 'Main Branch',
          'actor_email': 'manager@houseofsauces.example',
          'created_at': '2026-11-08T18:30:00.000Z',
          'details': {'paymentMode': 'cash', 'orderType': 'delivery'},
        },
      ];
}

ThemeData _theme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB63A27)),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF8F6F2),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
    );

Future<Uint8List> _capture(
  WidgetTester tester,
  Widget screen,
  String name, {
  bool owner = true,
  Future<void> Function(WidgetTester tester)? prepare,
}) async {
  const pixelRatio = 1.2;
  tester.view.devicePixelRatio = pixelRatio;
  tester.view.physicalSize = const Size(432, 960);
  final state = _PreviewState(owner: owner);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        home: RepaintBoundary(key: _screenKey, child: screen),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
  if (prepare != null) {
    await prepare(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
  }
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_screenKey));
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data;
  });
  if (bytes == null) throw StateError('Could not encode $name');
  return bytes.buffer.asUint8List();
}

void main() {
  testWidgets('capture customer preview screens', (tester) async {
    final directory = Directory('../customer_preview');
    await directory.create(recursive: true);

    Future<void> save(
      String name,
      Widget screen, {
      bool owner = true,
      Future<void> Function(WidgetTester tester)? prepare,
    }) async {
      // ignore: avoid_print
      print('Capturing $name');
      final bytes = await _capture(
        tester,
        screen,
        name,
        owner: owner,
        prepare: prepare,
      );
      await File('${directory.path}${Platform.pathSeparator}$name')
          .writeAsBytes(bytes);
    }

    await save('01-login.png', const LoginScreen(), owner: false);
    await save('02-owner-overview.png', const HomeShell());
    await save(
      '03-owner-quick-filters.png',
      const HomeShell(),
      prepare: (tester) async {
        await tester.ensureVisible(find.text('Quick sales filters'));
      },
    );
    await save(
      '04-owner-branch-breakdown.png',
      const HomeShell(),
      prepare: (tester) async {
        await tester.ensureVisible(find.text('Overall branch-wise breakup'));
      },
    );
    await save(
      '05-owner-sales.png',
      const HomeShell(),
      prepare: (tester) async {
        await tester.tap(find.text('Sales').last);
      },
    );
    await save('06-sale-details.png', SaleDetailScreen(sale: _sales.first));
    await save(
      '07-owner-expenses.png',
      const HomeShell(),
      prepare: (tester) async {
        await tester.tap(find.text('Expenses').last);
      },
    );
    await save(
      '08-expense-details.png',
      ExpenseDetailScreen(expense: _expenses.first),
    );
    await save(
      '09-profit-breakdown.png',
      ProfitBreakdownScreen(
        from: '2026-11-01T00:00:00.000Z',
        to: '2026-11-09T00:00:00.000Z',
      ),
    );
    await save(
      '10-pending-approvals.png',
      const ExpensesScreen(pendingOnly: true),
    );
    await save(
      '11-menu.png',
      const HomeShell(),
      prepare: (tester) async {
        await tester.tap(find.text('Menu').last);
      },
    );
    await save(
      '12-add-menu-product.png',
      MenuProductFormScreen(existingMenu: Future.value(_menu)),
    );
    await save(
      '13-top-pizzas.png',
      const HomeShell(),
      prepare: (tester) async {
        await tester.tap(find.text('Top pizzas').last);
      },
    );
    await save('14-branches-access.png', const BranchManagementScreen());
    await save(
      '15-audit-history.png',
      const AuditLogScreen(),
      prepare: (tester) async {
        await tester.tap(find.text('sale recorded'));
      },
    );
    await save(
      '16-admin-overview.png',
      const HomeShell(),
      owner: false,
    );
    await save(
      '17-admin-sales-log.png',
      const HomeShell(),
      owner: false,
      prepare: (tester) async {
        await tester.tap(find.text('Sales log').last);
      },
    );
    await save(
      '18-record-sale.png',
      const RecordSaleScreen(),
      owner: false,
    );
    await save(
      '19-admin-expenses.png',
      const HomeShell(),
      owner: false,
      prepare: (tester) async {
        await tester.tap(find.text('Expenses').last);
      },
    );
    await save(
      '20-request-expense.png',
      const AddExpenseScreen(),
      owner: false,
    );
    await save(
      '21-branch-profit-breakdown.png',
      const ProfitBreakdownScreen(
        branchId: _branchId,
        branchName: 'Main Branch',
        from: '2026-11-01T00:00:00.000Z',
        to: '2026-11-09T00:00:00.000Z',
        paymentMode: 'cash',
        orderType: 'delivery',
        category: 'Regular Flavour Pizzas',
      ),
    );

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
