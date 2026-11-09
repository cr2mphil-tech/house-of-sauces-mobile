import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'menu_excel.dart';
import 'models.dart';
import 'print_service.dart';
import 'widgets/password_visibility_field.dart';

final _money = NumberFormat.currency(symbol: 'Rs ', decimalDigits: 0);
final _date = DateFormat('dd MMM, hh:mm a');

String _paymentLabel(String mode) => switch (mode) {
      'cash' => 'Cash',
      'bank_transfer' => 'Bank transfer',
      'personal_use' => 'Personal use',
      _ => mode,
    };

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().login(_email.text.trim(), _password.text);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.local_pizza,
                          size: 72, color: Color(0xFFB63A27)),
                      const SizedBox(height: 16),
                      Text('House of Sauces',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('Branch operations & owner dashboard',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined)),
                        validator: (value) =>
                            value != null && value.contains('@')
                                ? null
                                : 'Enter a valid email address',
                      ),
                      const SizedBox(height: 14),
                      PasswordVisibilityField(
                        controller: _password,
                        labelText: 'Password',
                        validator: (value) => value != null && value.isNotEmpty
                            ? null
                            : 'Password is required',
                        onSubmitted: (_) => _login(),
                      ),
                      if (context.watch<AppState>().sessionRestoreError !=
                          null) ...[
                        const SizedBox(height: 12),
                        Text(
                          context.watch<AppState>().sessionRestoreError!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      ],
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: _busy ? null : _login,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: _busy
                              ? const CircularProgressIndicator()
                              : const Text('Sign in'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final owner = context.watch<AppState>().user?.isOwner ?? false;
    final pages = owner
        ? const [
            DashboardScreen(),
            SalesScreen(),
            ExpensesScreen(),
            MenuScreen(),
            HotSellingScreen()
          ]
        : const [
            DashboardScreen(),
            SalesScreen(),
            ExpensesScreen(),
            SalesScreen()
          ];
    final labels = owner
        ? const ['Overview', 'Sales', 'Expenses', 'Menu', 'Top pizzas']
        : const ['Overview', 'Record sale', 'Expenses', 'Sales log'];
    final icons = owner
        ? const [
            Icons.dashboard_outlined,
            Icons.receipt_long,
            Icons.payments_outlined,
            Icons.restaurant_menu,
            Icons.trending_up
          ]
        : const [
            Icons.dashboard_outlined,
            Icons.add_shopping_cart,
            Icons.request_quote_outlined,
            Icons.receipt_long
          ];
    if (_index >= pages.length) _index = 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('House of Sauces'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => context.read<AppState>().logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: List.generate(
          labels.length,
          (index) => NavigationDestination(
              icon: Icon(icons[index]), label: labels[index]),
        ),
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _period = 'Weekly';
  DateTimeRange? _customRange;
  List<Branch>? _branches;
  Future<Map<String, dynamic>>? _summary;
  Future<List<Sale>>? _sales;
  Future<List<Map<String, dynamic>>>? _branchSummaries;
  Future<List<MenuItem>>? _menuItems;
  String? _lastBranchId;
  String? _paymentMode;
  String? _orderType;
  String? _category;
  bool _printing = false;

  (String?, String?) get _range {
    final now = DateTime.now();
    final range = _customRange ??
        switch (_period) {
          'Session' => DateTimeRange(
              start: DateTime(now.year, now.month, now.day), end: now),
          'Monthly' =>
            DateTimeRange(start: DateTime(now.year, now.month), end: now),
          _ => DateTimeRange(
              start: now.subtract(const Duration(days: 6)), end: now),
        };
    final endExclusive =
        DateTime(range.end.year, range.end.month, range.end.day + 1);
    return (
      range.start.toUtc().toIso8601String(),
      endExclusive.toUtc().toIso8601String()
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final branchId = context.read<AppState>().selectedBranchId;
    if (_lastBranchId != branchId) {
      _lastBranchId = branchId;
      _reload();
    }
  }

  void _reload() {
    final range = _range;
    final state = context.read<AppState>();
    _summary = state.summary(
      from: range.$1,
      to: range.$2,
      paymentMode: _paymentMode,
      orderType: _orderType,
      category: _category,
    );
    _sales = state.sales(
      from: range.$1,
      to: range.$2,
      paymentMode: _paymentMode,
      orderType: _orderType,
      category: _category,
    );
    if (state.user?.isOwner == true) {
      _branchSummaries = state.branchSummaries(
        from: range.$1,
        to: range.$2,
        branchId: state.selectedBranchId,
        paymentMode: _paymentMode,
        orderType: _orderType,
        category: _category,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _lastBranchId = context.read<AppState>().selectedBranchId;
    _reload();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final state = context.read<AppState>();
      if (state.user?.isOwner == true) {
        setState(() {
          _menuItems = state.menu();
        });
        try {
          final branches = await state.branches();
          if (!mounted) return;
          setState(() => _branches = branches);
        } catch (error) {
          if (mounted) _showError(context, error);
        }
      }
    });
  }

  Future<void> _chooseCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customRange,
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _period = 'Custom';
        _reload();
      });
    }
  }

  Future<void> _printReport() async {
    final state = context.read<AppState>();
    setState(() => _printing = true);
    try {
      final range = _range;
      final values = await Future.wait<Object>([
        state.summary(
          from: range.$1,
          to: range.$2,
          paymentMode: _paymentMode,
          orderType: _orderType,
          category: _category,
        ),
        state.sales(
          from: range.$1,
          to: range.$2,
          paymentMode: _paymentMode,
          orderType: _orderType,
          category: _category,
        ),
        state.expenses(from: range.$1, to: range.$2),
        state.branchSummaries(
          from: range.$1,
          to: range.$2,
          branchId: state.selectedBranchId,
          paymentMode: _paymentMode,
          orderType: _orderType,
          category: _category,
        ),
      ]);
      final branches = _branches ?? await state.branches();
      final selectedBranches =
          branches.where((branch) => branch.id == state.selectedBranchId);
      final branchName = state.selectedBranchId == null
          ? 'All branches'
          : selectedBranches.isEmpty
              ? 'Selected branch'
              : selectedBranches.first.name;
      final rangeLabel = _customRange == null
          ? _period
          : '${DateFormat('dd MMM yyyy').format(_customRange!.start)} – ${DateFormat('dd MMM yyyy').format(_customRange!.end)}';
      await printOwnerReport(
        summary: values[0] as Map<String, dynamic>,
        sales: values[1] as List<Sale>,
        expenses: values[2] as List<Expense>,
        period: rangeLabel,
        branch: branchName,
        filters: _activeFilterLabels,
        branchSummaries: values[3] as List<Map<String, dynamic>>,
      );
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  List<String> get _activeFilterLabels => [
        if (_paymentMode != null) _paymentLabel(_paymentMode!),
        if (_orderType != null)
          _orderType == 'delivery' ? 'Delivery' : 'Pick-up',
        if (_category != null) _category!,
      ];

  void _updateFilters({
    String? paymentMode,
    String? orderType,
    String? category,
    bool clearPayment = false,
    bool clearOrderType = false,
    bool clearCategory = false,
  }) {
    setState(() {
      if (clearPayment || paymentMode != null) {
        _paymentMode = clearPayment ? null : paymentMode;
      }
      if (clearOrderType || orderType != null) {
        _orderType = clearOrderType ? null : orderType;
      }
      if (clearCategory || category != null) {
        _category = clearCategory ? null : category;
      }
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final owner = state.user?.isOwner == true;
    return RefreshIndicator(
      onRefresh: () async => setState(_reload),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (owner)
            if (_branches != null)
              DropdownButtonFormField<String?>(
                key: ValueKey(state.selectedBranchId),
                initialValue: state.selectedBranchId,
                decoration: const InputDecoration(
                  labelText: 'Branch',
                  prefixIcon: Icon(Icons.storefront),
                  helperText: 'Choose a branch or view all branches',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('All branches')),
                  ..._branches!.map((branch) => DropdownMenuItem<String?>(
                      value: branch.id, child: Text(branch.name))),
                ],
                onChanged: (id) {
                  state.selectBranch(id);
                  setState(_reload);
                },
              )
            else
              const LinearProgressIndicator(),
          if (owner) const SizedBox(height: 12),
          Text(owner ? 'Owner dashboard' : 'Branch dashboard',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(owner
              ? 'Financial health across your operation'
              : 'Your branch performance and actions'),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            children: [
              for (final period in ['Session', 'Weekly', 'Monthly'])
                ChoiceChip(
                  label: Text(period),
                  selected: _period == period,
                  onSelected: (_) => setState(() {
                    _period = period;
                    _customRange = null;
                    _reload();
                  }),
                ),
              ActionChip(
                label: Text(_period == 'Custom' ? 'Custom dates' : 'Custom'),
                avatar: const Icon(Icons.date_range, size: 18),
                onPressed: _chooseCustomRange,
              ),
              if (owner)
                ActionChip(
                  avatar: _printing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.print_outlined, size: 18),
                  label: const Text('Print report'),
                  onPressed: _printing ? null : _printReport,
                ),
            ],
          ),
          if (owner) ...[
            const SizedBox(height: 8),
            _SectionCard(
              title: 'Quick sales filters',
              action: TextButton(
                onPressed: _paymentMode == null &&
                        _orderType == null &&
                        _category == null
                    ? null
                    : () => _updateFilters(
                          clearPayment: true,
                          clearOrderType: true,
                          clearCategory: true,
                        ),
                child: const Text('Clear'),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Payment'),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: _paymentMode == null,
                        onSelected: (_) => _updateFilters(clearPayment: true),
                      ),
                      ChoiceChip(
                        label: const Text('Cash'),
                        selected: _paymentMode == 'cash',
                        onSelected: (_) => _updateFilters(paymentMode: 'cash'),
                      ),
                      ChoiceChip(
                        label: const Text('Bank transfer'),
                        selected: _paymentMode == 'bank_transfer',
                        onSelected: (_) =>
                            _updateFilters(paymentMode: 'bank_transfer'),
                      ),
                      ChoiceChip(
                        label: const Text('Personal use'),
                        selected: _paymentMode == 'personal_use',
                        onSelected: (_) =>
                            _updateFilters(paymentMode: 'personal_use'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Order type'),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: _orderType == null,
                        onSelected: (_) => _updateFilters(clearOrderType: true),
                      ),
                      ChoiceChip(
                        label: const Text('Pick-up'),
                        selected: _orderType == 'pickup',
                        onSelected: (_) => _updateFilters(orderType: 'pickup'),
                      ),
                      ChoiceChip(
                        label: const Text('Delivery'),
                        selected: _orderType == 'delivery',
                        onSelected: (_) =>
                            _updateFilters(orderType: 'delivery'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Product category'),
                  FutureBuilder<List<MenuItem>>(
                    future: _menuItems,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _ErrorPanel(
                          error: snapshot.error!,
                          onRetry: () => setState(() =>
                              _menuItems = context.read<AppState>().menu()),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const LinearProgressIndicator();
                      }
                      final categories = snapshot.data!
                          .map((item) => item.category)
                          .where((category) => category.trim().isNotEmpty)
                          .toSet()
                          .toList()
                        ..sort();
                      return Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('All'),
                            selected: _category == null,
                            onSelected: (_) =>
                                _updateFilters(clearCategory: true),
                          ),
                          for (final category in categories)
                            ChoiceChip(
                              label: Text(category),
                              selected: _category == category,
                              onSelected: (_) =>
                                  _updateFilters(category: category),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          FutureBuilder<Map<String, dynamic>>(
            future: _summary,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _ErrorPanel(
                    error: snapshot.error!, onRetry: () => setState(_reload));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data!;
              final metrics = <Widget>[
                _MetricCard(
                    label: 'Gross revenue',
                    value: _money.format(_number(data['revenue'])),
                    icon: Icons.south_west,
                    onTap: () => _open(
                        context,
                        'Revenue transactions',
                        SalesScreen(
                          from: _range.$1,
                          to: _range.$2,
                          paymentMode: _paymentMode,
                          orderType: _orderType,
                          category: _category,
                        ))),
                if (owner)
                  _MetricCard(
                      label: 'Delivery charges',
                      value: _money.format(_number(data['delivery_revenue'])),
                      icon: Icons.delivery_dining,
                      onTap: () => _open(
                          context,
                          'Delivery sales',
                          SalesScreen(
                            from: _range.$1,
                            to: _range.$2,
                            orderType: 'delivery',
                            paymentMode: _paymentMode,
                            category: _category,
                          ))),
                _MetricCard(
                    label: 'Net profit*',
                    value: _money.format(_number(data['net_profit'])),
                    icon: Icons.account_balance_wallet_outlined,
                    onTap: () => _open(
                        context,
                        'Profit breakdown',
                        ProfitBreakdownScreen(
                          from: _range.$1,
                          to: _range.$2,
                          paymentMode: _paymentMode,
                          orderType: _orderType,
                          category: _category,
                        ))),
                if (owner)
                  _MetricCard(
                      label: 'Cash sales',
                      value: _money.format(_number(data['cash_revenue'])),
                      icon: Icons.money,
                      onTap: () => _open(
                          context,
                          'Cash sales',
                          SalesScreen(
                            from: _range.$1,
                            to: _range.$2,
                            paymentMode: 'cash',
                            orderType: _orderType,
                            category: _category,
                          ))),
                if (owner)
                  _MetricCard(
                      label: 'Bank transfers',
                      value:
                          _money.format(_number(data['bank_transfer_revenue'])),
                      icon: Icons.account_balance,
                      onTap: () => _open(
                          context,
                          'Bank transfer sales',
                          SalesScreen(
                            from: _range.$1,
                            to: _range.$2,
                            paymentMode: 'bank_transfer',
                            orderType: _orderType,
                            category: _category,
                          ))),
                if (owner)
                  _MetricCard(
                      label: 'Personal use · excluded from sales',
                      value:
                          _money.format(_number(data['personal_use_amount'])),
                      icon: Icons.person_outline,
                      onTap: () => _open(
                          context,
                          'Personal use records',
                          SalesScreen(
                            from: _range.$1,
                            to: _range.$2,
                            paymentMode: 'personal_use',
                            orderType: _orderType,
                            category: _category,
                          ))),
                _MetricCard(
                    label: 'Operating expenses',
                    value: _money.format(_number(data['expenses'])),
                    icon: Icons.payments_outlined,
                    onTap: () => _open(context, 'Expense records',
                        ExpensesScreen(from: _range.$1, to: _range.$2))),
                _MetricCard(
                    label: 'Pending approvals',
                    value: '${data['pending_count'] ?? 0}',
                    icon: Icons.pending_actions,
                    onTap: () => _open(
                        context,
                        'Pending approvals',
                        ExpensesScreen(
                            pendingOnly: true,
                            from: _range.$1,
                            to: _range.$2))),
              ];
              return GridView.count(
                crossAxisCount: MediaQuery.sizeOf(context).width > 640 ? 4 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.28,
                children: metrics,
              );
            },
          ),
          if (owner) ...[
            const SizedBox(height: 18),
            _SectionCard(
              title: 'Overall branch-wise breakup',
              action: const SizedBox.shrink(),
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _branchSummaries,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _ErrorPanel(
                      error: snapshot.error!,
                      onRetry: () => setState(_reload),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.data!.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No active branches found.'),
                    );
                  }
                  return Column(
                    children: [
                      for (final branch in snapshot.data!)
                        _BranchFinancialCard(
                          branch: branch,
                          onTap: () => _open(
                            context,
                            '${branch['branch_name']} breakdown',
                            ProfitBreakdownScreen(
                              from: _range.$1,
                              to: _range.$2,
                              branchId: branch['branch_id'] as String,
                              branchName: branch['branch_name'] as String,
                              paymentMode: _paymentMode,
                              orderType: _orderType,
                              category: _category,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Revenue activity',
            action: TextButton(
                onPressed: () => _open(
                    context,
                    'Sales transactions',
                    SalesScreen(
                      from: _range.$1,
                      to: _range.$2,
                      paymentMode: _paymentMode,
                      orderType: _orderType,
                      category: _category,
                    )),
                child: const Text('View sales')),
            child: FutureBuilder<List<Sale>>(
              future: _sales,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _ErrorPanel(
                      error: snapshot.error!, onRetry: () => setState(_reload));
                }
                if (!snapshot.hasData) {
                  return const SizedBox(
                      height: 140,
                      child: Center(child: CircularProgressIndicator()));
                }
                return InkWell(
                  onTap: () => _open(
                      context,
                      'Revenue transactions',
                      SalesScreen(
                        from: _range.$1,
                        to: _range.$2,
                        paymentMode: _paymentMode,
                        orderType: _orderType,
                        category: _category,
                      )),
                  child: _RevenueChart(sales: snapshot.data!),
                );
              },
            ),
          ),
          if (owner) ...[
            const SizedBox(height: 8),
            _SectionCard(
              title: 'Operations & records',
              action: const SizedBox.shrink(),
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.store_mall_directory_outlined),
                  title: const Text('Branches & admin access'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(context, 'Branches & access',
                      const BranchManagementScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Audit history'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      _open(context, 'Audit history', const AuditLogScreen()),
                ),
              ]),
            ),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 12, 4, 4),
            child: Text(
                '* Net profit is revenue less settled operating expenses; product costs are not yet tracked.',
                style: TextStyle(color: Colors.black54, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _RevenueChart extends StatelessWidget {
  const _RevenueChart({required this.sales});
  final List<Sale> sales;

  @override
  Widget build(BuildContext context) {
    final byDay = <DateTime, double>{};
    for (final sale
        in sales.where((sale) => sale.paymentMode != 'personal_use')) {
      final day = DateTime(
          sale.createdAt.year, sale.createdAt.month, sale.createdAt.day);
      byDay.update(day, (amount) => amount + sale.totalAmount,
          ifAbsent: () => sale.totalAmount);
    }
    final entries = byDay.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (entries.isEmpty) {
      return const SizedBox(
          height: 150, child: Center(child: Text('No sales for this period')));
    }
    return SizedBox(
      height: 190,
      child: LineChart(LineChartData(
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
              sideTitles: SideTitles(
            showTitles: true,
            interval:
                entries.length > 7 ? (entries.length / 5).ceilToDouble() : 1,
            getTitlesWidget: (value, _) {
              final index = value.toInt();
              if (index < 0 || index >= entries.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(DateFormat('d/M').format(entries[index].key),
                      style: const TextStyle(fontSize: 10)));
            },
          )),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var index = 0; index < entries.length; index++)
                FlSpot(index.toDouble(), entries[index].value)
            ],
            isCurved: true,
            color: Theme.of(context).colorScheme.primary,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
                show: true,
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.1)),
          ),
        ],
      )),
    );
  }
}

class SalesScreen extends StatefulWidget {
  const SalesScreen(
      {super.key,
      this.from,
      this.to,
      this.menuSizeId,
      this.branchId,
      this.paymentMode,
      this.orderType,
      this.category});
  final String? from;
  final String? to;
  final String? menuSizeId;
  final String? branchId;
  final String? paymentMode;
  final String? orderType;
  final String? category;

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  late Future<List<Sale>> _sales;

  @override
  void initState() {
    super.initState();
    _sales = context.read<AppState>().sales(
          from: widget.from,
          to: widget.to,
          menuSizeId: widget.menuSizeId,
          branchId: widget.branchId,
          paymentMode: widget.paymentMode,
          orderType: widget.orderType,
          category: widget.category,
        );
  }

  Future<void> _refresh() async {
    setState(() => _sales = context.read<AppState>().sales(
          from: widget.from,
          to: widget.to,
          menuSizeId: widget.menuSizeId,
          branchId: widget.branchId,
          paymentMode: widget.paymentMode,
          orderType: widget.orderType,
          category: widget.category,
        ));
    await _sales;
  }

  Future<void> _printOrders(List<Sale> sales) async {
    try {
      await printSalesOrders(sales);
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<void> _record() async {
    final state = context.read<AppState>();
    if (state.user?.isOwner == true && state.selectedBranchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Choose a branch on the dashboard before recording a sale.')));
      return;
    }
    final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const RecordSaleScreen()));
    if (result == true && mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final owner = context.watch<AppState>().user?.isOwner == true;
    return Scaffold(
      body: FutureBuilder<List<Sale>>(
        future: _sales,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorPanel(error: snapshot.error!, onRetry: _refresh);
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final salesByOrder = <String, List<Sale>>{};
          for (final sale in snapshot.data!) {
            final orderId =
                sale.orderGroupId.isEmpty ? sale.id : sale.orderGroupId;
            salesByOrder.putIfAbsent(orderId, () => []).add(sale);
          }
          final orders = salesByOrder.values.toList()
            ..sort((a, b) => b.first.createdAt.compareTo(a.first.createdAt));
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: snapshot.data!.isEmpty
                        ? null
                        : () => _printOrders(snapshot.data!),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Print sales orders'),
                  ),
                ),
                if (orders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: Text('No sales recorded yet')),
                  ),
                ...orders.map((order) {
                  final sale = order.first;
                  final total = order.fold<double>(
                      0, (sum, line) => sum + line.totalAmount);
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(sale.orderType == 'delivery'
                            ? Icons.delivery_dining
                            : Icons.local_pizza),
                      ),
                      title: Text(sale.orderType == 'delivery' &&
                              sale.customerName != null
                          ? sale.customerName!
                          : '${sale.pizzaName} · ${sale.sizeName}'),
                      subtitle: Text([
                        '${order.length} item${order.length == 1 ? '' : 's'} · ${sale.orderType} · ${_paymentLabel(sale.paymentMode)}${owner && sale.branchName.isNotEmpty ? ' · ${sale.branchName}' : ''}',
                        if (sale.customerPhone != null)
                          'Phone: ${sale.customerPhone}',
                        order
                            .map((line) =>
                                '${line.pizzaName} · ${line.sizeName} × ${line.quantity}')
                            .join(', '),
                        'Order ${(sale.orderGroupId.isEmpty ? sale.id : sale.orderGroupId).substring(0, 8).toUpperCase()} · ${_date.format(sale.createdAt.toLocal())}',
                      ].join('\n')),
                      isThreeLine: true,
                      trailing: Text(_money.format(total),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SalesOrderDetailScreen(sales: order),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _record,
          icon: const Icon(Icons.add),
          label: const Text('Record sale')),
    );
  }
}

class RecordSaleScreen extends StatefulWidget {
  const RecordSaleScreen({super.key});

  @override
  State<RecordSaleScreen> createState() => _RecordSaleScreenState();
}

class _OrderLineDraft {
  MenuItem? item;
  MenuSize? size;
  final quantity = TextEditingController(text: '1');
}

class _RecordSaleScreenState extends State<RecordSaleScreen> {
  final _form = GlobalKey<FormState>();
  final _customerName = TextEditingController();
  final _customerPhone = TextEditingController();
  final _deliveryFee = TextEditingController(text: '0');
  late Future<List<MenuItem>> _menu;
  final List<_OrderLineDraft> _lines = [_OrderLineDraft()];
  String _orderType = 'pickup';
  String _paymentMode = 'cash';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _menu = context.read<AppState>().menu();
  }

  @override
  void dispose() {
    _customerName.dispose();
    _customerPhone.dispose();
    _deliveryFee.dispose();
    for (final line in _lines) {
      line.quantity.dispose();
    }
    super.dispose();
  }

  double get _itemsSubtotal => _lines.fold<double>(
        0,
        (total, line) =>
            total +
            (line.size?.price ?? 0) * (int.tryParse(line.quantity.text) ?? 0),
      );

  double get _deliveryCharge => _orderType == 'delivery'
      ? double.tryParse(_deliveryFee.text.trim()) ?? 0
      : 0;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final state = context.read<AppState>();
    if (state.user?.isOwner == true && state.selectedBranchId == null) {
      _showError(
          context, Exception('Select a branch before recording a sale.'));
      return;
    }
    setState(() => _busy = true);
    try {
      await state.recordSale(
        items: [
          for (final line in _lines)
            {
              'menuSizeId': line.size!.id,
              'quantity': int.parse(line.quantity.text),
            },
        ],
        orderType: _orderType,
        paymentMode: _paymentMode,
        deliveryFee: _deliveryCharge,
        customerName:
            _orderType == 'delivery' ? _customerName.text.trim() : null,
        customerPhone:
            _orderType == 'delivery' ? _customerPhone.text.trim() : null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Record a sale')),
        body: FutureBuilder<List<MenuItem>>(
          future: _menu,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorPanel(
                  error: snapshot.error!,
                  onRetry: () =>
                      setState(() => _menu = context.read<AppState>().menu()));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.data!.isEmpty) {
              return const Center(
                  child: Text('Ask the owner to import the pizza menu first.'));
            }
            final items = snapshot.data!;
            return Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text('Order items',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (var index = 0; index < _lines.length; index++)
                    Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text('Item ${index + 1}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                                ),
                                if (_lines.length > 1)
                                  IconButton(
                                    tooltip: 'Remove item',
                                    onPressed: () => setState(() {
                                      _lines.removeAt(index).quantity.dispose();
                                    }),
                                    icon:
                                        const Icon(Icons.remove_circle_outline),
                                  ),
                              ],
                            ),
                            DropdownButtonFormField<MenuItem>(
                              key: ObjectKey(_lines[index]),
                              initialValue: _lines[index].item,
                              decoration: const InputDecoration(
                                  labelText: 'Product category and item'),
                              items: items
                                  .map((item) => DropdownMenuItem(
                                        value: item,
                                        child: Text(
                                          '${item.category} · ${item.name}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (value) => setState(() {
                                _lines[index].item = value;
                                _lines[index].size = null;
                              }),
                              validator: (value) =>
                                  value == null ? 'Choose a product' : null,
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<MenuSize>(
                              key: ValueKey(
                                  'size-${identityHashCode(_lines[index])}-${_lines[index].item?.id}'),
                              initialValue: _lines[index].size,
                              decoration:
                                  const InputDecoration(labelText: 'Size'),
                              items: (_lines[index].item?.sizes ?? [])
                                  .map((size) => DropdownMenuItem(
                                        value: size,
                                        child: Text(
                                            '${size.name} · ${_money.format(size.price)}'),
                                      ))
                                  .toList(),
                              onChanged: (value) =>
                                  setState(() => _lines[index].size = value),
                              validator: (value) =>
                                  value == null ? 'Choose a size' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _lines[index].quantity,
                              keyboardType: TextInputType.number,
                              decoration:
                                  const InputDecoration(labelText: 'Quantity'),
                              validator: (value) {
                                final count = int.tryParse(value ?? '');
                                return count != null &&
                                        count > 0 &&
                                        count <= 1000
                                    ? null
                                    : 'Enter a quantity from 1 to 1000';
                              },
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          setState(() => _lines.add(_OrderLineDraft())),
                      icon: const Icon(Icons.add),
                      label: const Text('Add more order items'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _orderType,
                    decoration: const InputDecoration(labelText: 'Order type'),
                    items: const [
                      DropdownMenuItem(value: 'pickup', child: Text('Pick-up')),
                      DropdownMenuItem(
                          value: 'delivery', child: Text('Delivery'))
                    ],
                    onChanged: (value) => setState(() => _orderType = value!),
                  ),
                  if (_orderType == 'delivery') ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _customerName,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: 'Customer name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) => _orderType == 'delivery' &&
                              (value == null || value.trim().isEmpty)
                          ? 'Enter the delivery customer name'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _customerPhone,
                      keyboardType: TextInputType.phone,
                      maxLength: 40,
                      decoration: const InputDecoration(
                        labelText: 'Customer phone number',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      validator: (value) {
                        if (_orderType != 'delivery') return null;
                        if (value == null ||
                            !RegExp(r'^[0-9+() -]{7,40}$')
                                .hasMatch(value.trim())) {
                          return 'Enter a valid phone number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _deliveryFee,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Delivery charges',
                        prefixText: 'Rs ',
                        helperText:
                            'Enter the delivery charge for this whole order.',
                      ),
                      validator: (value) {
                        if (_orderType != 'delivery') return null;
                        final amount = double.tryParse(value ?? '');
                        return amount == null || amount < 0 || amount > 100000
                            ? 'Enter a delivery charge from Rs 0 to Rs 100,000'
                            : null;
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          _orderTotalRow(
                              'Items subtotal', _money.format(_itemsSubtotal)),
                          if (_orderType == 'delivery')
                            _orderTotalRow('Delivery charges',
                                _money.format(_deliveryCharge)),
                          const Divider(),
                          _orderTotalRow(
                            _paymentMode == 'personal_use'
                                ? 'Personal-use value · not counted as sales'
                                : 'Accumulated order total',
                            _money.format(_itemsSubtotal + _deliveryCharge),
                            bold: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _paymentMode,
                    decoration:
                        const InputDecoration(labelText: 'Payment mode'),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      DropdownMenuItem(
                          value: 'bank_transfer',
                          child: Text('Direct bank transfer')),
                      DropdownMenuItem(
                        value: 'personal_use',
                        child: Text('Personal use · excluded from sales'),
                      ),
                    ],
                    onChanged: (value) => setState(() => _paymentMode = value!),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const CircularProgressIndicator()
                          : Text(_paymentMode == 'personal_use'
                              ? 'Save personal-use record'
                              : 'Save sale')),
                ],
              ),
            );
          },
        ),
      );
}

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen(
      {super.key, this.pendingOnly = false, this.from, this.to});
  final bool pendingOnly;
  final String? from;
  final String? to;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  late Future<List<Expense>> _expenses;

  @override
  void initState() {
    super.initState();
    _expenses =
        context.read<AppState>().expenses(from: widget.from, to: widget.to);
  }

  Future<void> _refresh() async {
    setState(() => _expenses =
        context.read<AppState>().expenses(from: widget.from, to: widget.to));
    await _expenses;
  }

  Future<void> _addExpense() async {
    final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const AddExpenseScreen()));
    if (result == true && mounted) _refresh();
  }

  Future<void> _settle(Expense expense) async {
    final mode = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          const ListTile(title: Text('Approve and settle expense')),
          ListTile(
              leading: const Icon(Icons.money),
              title: const Text('Adjust branch cash receipts'),
              onTap: () => Navigator.pop(context, 'cash_adjustment')),
          ListTile(
              leading: const Icon(Icons.account_balance),
              title: const Text('Settle by bank transfer'),
              onTap: () => Navigator.pop(context, 'bank_transfer')),
        ]),
      ),
    );
    if (mode == null || !mounted) return;
    final state = context.read<AppState>();
    try {
      await state.settleExpense(expense.id, mode);
      await _refresh();
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = context.watch<AppState>().user?.isOwner == true;
    return Scaffold(
      body: FutureBuilder<List<Expense>>(
        future: _expenses,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorPanel(error: snapshot.error!, onRetry: _refresh);
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final expenses = snapshot.data!
              .where((expense) =>
                  !widget.pendingOnly || expense.status == 'pending')
              .toList();
          if (expenses.isEmpty) {
            return const Center(child: Text('No expense requests found'));
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: expenses.length,
              itemBuilder: (context, index) {
                final expense = expenses[index];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                        child: Icon(expense.status == 'pending'
                            ? Icons.hourglass_top
                            : Icons.check)),
                    title: Text(expense.financialHead),
                    subtitle: Text(
                        '${expense.description}\n${expense.branchName.isEmpty ? '' : '${expense.branchName} · '}${_date.format(expense.createdAt.toLocal())} · ${expense.status}${expense.settlementMode == null ? '' : ' · ${expense.settlementMode}'}'),
                    isThreeLine: true,
                    trailing: owner && expense.status == 'pending'
                        ? TextButton(
                            onPressed: () => _settle(expense),
                            child: const Text('Review'))
                        : Text(_money.format(expense.amount),
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () => _open(context, 'Expense details',
                        ExpenseDetailScreen(expense: expense)),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: owner
          ? null
          : FloatingActionButton.extended(
              onPressed: _addExpense,
              icon: const Icon(Icons.add),
              label: const Text('Request expense')),
    );
  }
}

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _form = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  String? _head;
  bool _busy = false;
  late Future<List<String>> _heads;

  @override
  void initState() {
    super.initState();
    _heads = context.read<AppState>().expenseHeads();
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<AppState>().submitExpense(
            financialHead: _head!,
            description: _description.text.trim(),
            amount: double.parse(_amount.text),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Submitted for owner approval; no payment was made.')));
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Request an expense')),
        body: FutureBuilder<List<String>>(
          future: _heads,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorPanel(
                  error: snapshot.error!,
                  onRetry: () => setState(
                      () => _heads = context.read<AppState>().expenseHeads()));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final heads = snapshot.data!;
            return Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(20), children: [
                const Text(
                    'All requests remain pending until the owner approves and settles them.'),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: _head,
                  decoration:
                      const InputDecoration(labelText: 'Financial head'),
                  items: heads
                      .map((head) =>
                          DropdownMenuItem(value: head, child: Text(head)))
                      .toList(),
                  onChanged: (value) => setState(() => _head = value),
                  validator: (value) =>
                      value == null ? 'Choose a financial head' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                    controller: _description,
                    decoration: const InputDecoration(labelText: 'Description'),
                    validator: (value) =>
                        value != null && value.trim().isNotEmpty
                            ? null
                            : 'Description is required'),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Amount', prefixText: 'Rs '),
                  validator: (value) {
                    final amount = double.tryParse(value ?? '');
                    return amount != null && amount > 0
                        ? null
                        : 'Enter a valid amount';
                  },
                ),
                const SizedBox(height: 24),
                FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const CircularProgressIndicator()
                        : const Text('Submit for approval')),
              ]),
            );
          },
        ),
      );
}

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  late Future<List<MenuItem>> _menu;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _menu = context.read<AppState>().menu();
  }

  Future<void> _import() async {
    List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
    } catch (error) {
      if (mounted) {
        _showError(
          context,
          Exception('Could not access files on this device: $error'),
        );
      }
      return;
    }
    if (files.isEmpty || !mounted) return;
    late final List<Map<String, dynamic>> records;
    try {
      final bytes = await files.single.readAsBytes();
      records = parseMenuWorkbook(bytes);
    } catch (error) {
      if (mounted) _showError(context, error);
      return;
    }
    if (!mounted) return;
    final state = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await state.importMenu(records);
      if (mounted) {
        setState(() => _menu = context.read<AppState>().menu());
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Menu imported successfully.')));
      }
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadTemplate() async {
    setState(() => _busy = true);
    try {
      final menu = await context.read<AppState>().menu();
      final categories = menu.map((item) => item.category);
      final sizes = menu.expand((item) => item.sizes.map((size) => size.name));
      final bytes =
          buildMenuTemplateBytes(categories: categories, sizes: sizes);
      final saved = await FilePicker.saveFile(
        fileName: 'house_of_sauces_menu_template.xlsx',
        bytes: bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        dialogTitle: 'Save House of Sauces menu template',
      );
      if (!mounted || saved == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Menu template saved: ${saved.path}')),
      );
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createProduct() async {
    final added = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => MenuProductFormScreen(existingMenu: _menu),
    ));
    if (added == true && mounted) {
      setState(() => _menu = context.read<AppState>().menu());
    }
  }

  Future<void> _editPrice(MenuItem item, MenuSize size) async {
    final controller =
        TextEditingController(text: size.price.toStringAsFixed(0));
    final formKey = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Edit ${item.name} · ${size.name}'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'New price',
              prefixText: 'Rs ',
            ),
            validator: (value) {
              final price = double.tryParse(value ?? '');
              return price == null || price <= 0 || price > 100000
                  ? 'Enter a price from Rs 0.01 to Rs 100,000'
                  : null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Save price'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      controller.dispose();
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AppState>().updateMenuSizePrice(
            sizeId: size.id,
            price: double.parse(controller.text.trim()),
          );
      if (mounted) {
        setState(() => _menu = context.read<AppState>().menu());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Menu price updated.')),
        );
      }
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      controller.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: FutureBuilder<List<MenuItem>>(
          future: _menu,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorPanel(
                  error: snapshot.error!,
                  onRetry: () =>
                      setState(() => _menu = context.read<AppState>().menu()));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Excel menu template',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        const Text(
                            'Use the exact columns: Pizza Name, Category, Size, Base Price, Active and optional Description. Existing categories and sizes are listed in the dropdown suggestions.'),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _downloadTemplate,
                          icon: const Icon(Icons.download),
                          label: const Text('Download XLSX template'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (snapshot.data!.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                        'No menu items yet. The default workbook menu is seeded by the API at startup.'),
                  ),
                ...snapshot.data!.map((item) => Card(
                      child: ExpansionTile(
                        leading: const CircleAvatar(
                            child: Icon(Icons.restaurant_menu)),
                        title: Text(item.name),
                        subtitle: Text(item.description.isEmpty
                            ? item.category
                            : '${item.category}\n${item.description}'),
                        children: item.sizes
                            .map((size) => ListTile(
                                title: Text(size.name),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_money.format(size.price)),
                                    IconButton(
                                      tooltip: 'Edit price',
                                      onPressed: _busy
                                          ? null
                                          : () => _editPrice(item, size),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                  ],
                                )))
                            .toList(),
                      ),
                    )),
              ],
            );
          },
        ),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton.extended(
              heroTag: 'add-menu-product',
              tooltip: 'Add product',
              onPressed: _busy ? null : _createProduct,
              icon: const Icon(Icons.add),
              label: const Text('Add product manually'),
            ),
            const SizedBox(height: 10),
            FloatingActionButton.extended(
              heroTag: 'import-menu-xlsx',
              onPressed: _busy ? null : _import,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_file),
              label: const Text('Import XLSX'),
            ),
          ],
        ),
      );
}

class MenuProductFormScreen extends StatefulWidget {
  const MenuProductFormScreen({required this.existingMenu, super.key});

  final Future<List<MenuItem>> existingMenu;

  @override
  State<MenuProductFormScreen> createState() => _MenuProductFormScreenState();
}

class _MenuProductFormScreenState extends State<MenuProductFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _description = TextEditingController();
  final _sizeNames = [TextEditingController()];
  final _prices = [TextEditingController()];
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _description.dispose();
    for (final controller in [..._sizeNames, ..._prices]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final sizeNames = _sizeNames
        .map((controller) => controller.text.trim().toLowerCase())
        .toSet();
    if (sizeNames.length != _sizeNames.length) {
      _showError(
        context,
        const FormatException('Each size or option must have a unique name.'),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AppState>().createMenuProduct(
        name: _name.text.trim(),
        category: _category.text.trim(),
        description: _description.text.trim(),
        sizes: [
          for (var index = 0; index < _sizeNames.length; index++)
            {
              'name': _sizeNames[index].text.trim(),
              'price': double.parse(_prices[index].text.trim()),
            },
        ],
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Add menu product')),
        body: FutureBuilder<List<MenuItem>>(
          future: widget.existingMenu,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorPanel(
                  error: snapshot.error!, onRetry: () => setState(() {}));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final categories = snapshot.data!
                .map((item) => item.category)
                .toSet()
                .toList()
              ..sort();
            final knownSizes = snapshot.data!
                .expand((item) => item.sizes.map((size) => size.name))
                .toSet()
                .toList()
              ..sort();
            return Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  TextFormField(
                    controller: _name,
                    decoration:
                        const InputDecoration(labelText: 'Product name'),
                    maxLength: 120,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter a product name'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _category,
                    decoration: InputDecoration(
                      labelText: 'Category',
                      helperText: categories.isEmpty
                          ? 'Choose an existing category label or enter a new one.'
                          : 'Existing categories: ${categories.join(', ')}',
                    ),
                    maxLength: 80,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter a category'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _description,
                    decoration: const InputDecoration(
                      labelText: 'Description / deal contents (optional)',
                    ),
                    maxLength: 500,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  Text('Sizes and prices',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (var index = 0; index < _sizeNames.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _sizeNames[index],
                              decoration: InputDecoration(
                                labelText: 'Size / option ${index + 1}',
                                helperText: knownSizes.isEmpty
                                    ? null
                                    : 'Existing: ${knownSizes.join(', ')}',
                              ),
                              maxLength: 40,
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? 'Enter a size'
                                      : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _prices[index],
                              decoration: const InputDecoration(
                                  labelText: 'Price (Rs.)'),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              validator: (value) {
                                final price = double.tryParse(value ?? '');
                                return price == null || price <= 0
                                    ? 'Enter a positive price'
                                    : null;
                              },
                            ),
                          ),
                          if (_sizeNames.length > 1)
                            IconButton(
                              tooltip: 'Remove size',
                              onPressed: () => setState(() {
                                _sizeNames.removeAt(index).dispose();
                                _prices.removeAt(index).dispose();
                              }),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                        ],
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() {
                        _sizeNames.add(TextEditingController());
                        _prices.add(TextEditingController());
                      }),
                      icon: const Icon(Icons.add),
                      label: const Text('Add size / price'),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: const Text('Save product'),
                  ),
                ],
              ),
            );
          },
        ),
      );
}

class HotSellingScreen extends StatefulWidget {
  const HotSellingScreen({super.key});

  @override
  State<HotSellingScreen> createState() => _HotSellingScreenState();
}

class _HotSellingScreenState extends State<HotSellingScreen> {
  late Future<List<Map<String, dynamic>>> _items;
  late Future<List<Branch>> _branches;
  late Future<List<MenuItem>> _menu;
  DateTimeRange? _customRange;
  String? _category;
  String? _size;
  String _period = 'Monthly';

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _branches = state.branches();
    _menu = state.menu();
    _reload();
  }

  (String?, String?) get _range {
    final now = DateTime.now();
    final range = _customRange ??
        switch (_period) {
          'Session' => DateTimeRange(
              start: DateTime(now.year, now.month, now.day), end: now),
          'Weekly' => DateTimeRange(
              start: now.subtract(const Duration(days: 6)), end: now),
          _ => DateTimeRange(start: DateTime(now.year, now.month), end: now),
        };
    final endExclusive =
        DateTime(range.end.year, range.end.month, range.end.day + 1);
    return (
      range.start.toUtc().toIso8601String(),
      endExclusive.toUtc().toIso8601String()
    );
  }

  void _reload() {
    final range = _range;
    _items = context.read<AppState>().hotSelling(
          category: _category,
          size: _size,
          from: range.$1,
          to: range.$2,
        );
  }

  Future<void> _chooseRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customRange,
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _period = 'Custom';
        _reload();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        FutureBuilder<List<Branch>>(
          future: _branches,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorPanel(
                  error: snapshot.error!,
                  onRetry: () => setState(
                      () => _branches = context.read<AppState>().branches()));
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: DropdownButtonFormField<String?>(
                key: ValueKey(context.watch<AppState>().selectedBranchId),
                initialValue: context.watch<AppState>().selectedBranchId,
                decoration: const InputDecoration(labelText: 'Branch'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('All branches')),
                  ...snapshot.data!.map((branch) => DropdownMenuItem<String?>(
                      value: branch.id, child: Text(branch.name))),
                ],
                onChanged: (branchId) {
                  context.read<AppState>().selectBranch(branchId);
                  setState(_reload);
                },
              ),
            );
          },
        ),
        FutureBuilder<List<MenuItem>>(
          future: _menu,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorPanel(
                  error: snapshot.error!,
                  onRetry: () =>
                      setState(() => _menu = context.read<AppState>().menu()));
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final categories = snapshot.data!
                .map((item) => item.category)
                .toSet()
                .toList()
              ..sort();
            final sizes = snapshot.data!
                .where(
                    (item) => _category == null || item.category == _category)
                .expand((item) => item.sizes.map((size) => size.name))
                .toSet()
                .toList()
              ..sort();
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('All')),
                      ...categories.map((category) => DropdownMenuItem<String?>(
                          value: category, child: Text(category))),
                    ],
                    onChanged: (value) => setState(() {
                      _category = value;
                      if (_size != null && !sizes.contains(_size)) _size = null;
                      _reload();
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    key: ValueKey(_category),
                    initialValue: _size,
                    decoration: const InputDecoration(labelText: 'Size'),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('All')),
                      ...sizes.map((size) => DropdownMenuItem<String?>(
                          value: size, child: Text(size))),
                    ],
                    onChanged: (value) => setState(() {
                      _size = value;
                      _reload();
                    }),
                  ),
                ),
              ]),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Wrap(spacing: 8, children: [
            for (final period in ['Session', 'Weekly', 'Monthly'])
              ChoiceChip(
                label: Text(period),
                selected: _period == period,
                onSelected: (_) => setState(() {
                  _period = period;
                  _customRange = null;
                  _reload();
                }),
              ),
            ActionChip(
              label: Text(_period == 'Custom' ? 'Custom dates' : 'Custom'),
              avatar: const Icon(Icons.date_range, size: 18),
              onPressed: _chooseRange,
            ),
          ]),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _items,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _ErrorPanel(
                    error: snapshot.error!, onRetry: () => setState(_reload));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.isEmpty) {
                return const Center(
                    child: Text('No pizza sales to rank for this period'));
              }
              return ListView.builder(
                itemCount: snapshot.data!.length,
                itemBuilder: (context, index) {
                  final item = snapshot.data![index];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text('${index + 1}')),
                      title:
                          Text('${item['pizza_name']} · ${item['size_name']}'),
                      subtitle: Text(
                          '${item['category']} · ${item['branch_name']} · ${_money.format(_number(item['revenue']))}'),
                      trailing: Text('${item['quantity_sold']} sold',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      onTap: () {
                        final range = _range;
                        _open(
                          context,
                          'Sales for ${item['pizza_name']}',
                          SalesScreen(
                            from: range.$1,
                            to: range.$2,
                            menuSizeId: item['menu_size_id'] as String,
                            branchId: item['branch_id'] as String,
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]);
}

class SalesOrderDetailScreen extends StatelessWidget {
  const SalesOrderDetailScreen({required this.sales, super.key});

  final List<Sale> sales;

  Future<void> _print(BuildContext context) async {
    try {
      await printSalesOrderGroup(sales);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final first = sales.first;
    final subtotal = sales.fold<double>(
      0,
      (total, sale) => total + sale.unitPrice * sale.quantity,
    );
    final deliveryFee =
        sales.fold<double>(0, (total, sale) => total + sale.deliveryFee);
    final total =
        sales.fold<double>(0, (amount, sale) => amount + sale.totalAmount);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales order'),
        actions: [
          IconButton(
            tooltip: 'Print complete order',
            onPressed: () => _print(context),
            icon: const Icon(Icons.print_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Details(children: {
            'Order reference': first.orderGroupId,
            'Order type': first.orderType,
            'Payment': first.paymentMode,
            'Customer': first.customerName ?? 'Walk-in',
            if (first.customerPhone != null)
              'Customer phone': first.customerPhone!,
            'Branch': first.branchName,
            'Recorded': _date.format(first.createdAt.toLocal()),
            'Items subtotal': _money.format(subtotal),
            if (first.orderType == 'delivery')
              'Delivery charges': _money.format(deliveryFee),
            'Accumulated order total': _money.format(total),
          }),
          const SizedBox(height: 18),
          Text('Order items', style: Theme.of(context).textTheme.titleLarge),
          for (final sale in sales)
            Card(
              child: ListTile(
                title: Text('${sale.pizzaName} · ${sale.sizeName}'),
                subtitle: Text(
                    '${sale.category} · ${sale.quantity} × ${_money.format(sale.unitPrice)}'),
                trailing: Text(_money.format(sale.totalAmount)),
              ),
            ),
        ],
      ),
    );
  }
}

class SaleDetailScreen extends StatelessWidget {
  const SaleDetailScreen({required this.sale, super.key});
  final Sale sale;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Sales order'),
          actions: [
            IconButton(
              tooltip: 'Print sales order',
              onPressed: () async {
                try {
                  await printSalesOrder(sale);
                } catch (error) {
                  if (context.mounted) _showError(context, error);
                }
              },
              icon: const Icon(Icons.print_outlined),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _Details(children: {
            'Product': sale.pizzaName,
            'Category': sale.category,
            if (sale.productDescription.isNotEmpty)
              'Product details': sale.productDescription,
            'Size': sale.sizeName,
            'Quantity': '${sale.quantity}',
            'Items subtotal': _money.format(sale.unitPrice * sale.quantity),
            'Delivery fee': _money.format(sale.deliveryFee),
            'Order type': sale.orderType,
            'Payment': _paymentLabel(sale.paymentMode),
            if (sale.customerName != null) 'Customer': sale.customerName!,
            if (sale.customerPhone != null)
              'Customer phone': sale.customerPhone!,
            'Order reference': sale.orderGroupId,
            'Branch': sale.branchName,
            'Recorded': _date.format(sale.createdAt.toLocal()),
            'Total': _money.format(sale.totalAmount),
          }),
        ),
      );
}

class ProfitBreakdownScreen extends StatefulWidget {
  const ProfitBreakdownScreen({
    super.key,
    this.from,
    this.to,
    this.branchId,
    this.branchName,
    this.paymentMode,
    this.orderType,
    this.category,
  });
  final String? from;
  final String? to;
  final String? branchId;
  final String? branchName;
  final String? paymentMode;
  final String? orderType;
  final String? category;

  @override
  State<ProfitBreakdownScreen> createState() => _ProfitBreakdownScreenState();
}

class _ProfitBreakdownScreenState extends State<ProfitBreakdownScreen> {
  late Future<List<Object>> _breakdown;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final state = context.read<AppState>();
    _breakdown = Future.wait<Object>([
      state.sales(
        from: widget.from,
        to: widget.to,
        branchId: widget.branchId,
        paymentMode: widget.paymentMode,
        orderType: widget.orderType,
        category: widget.category,
      ),
      state.expenses(
        from: widget.from,
        to: widget.to,
        branchId: widget.branchId,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.branchName == null
              ? 'Profit breakdown'
              : '${widget.branchName} breakdown')),
      body: FutureBuilder<List<Object>>(
        future: _breakdown,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorPanel(
                error: snapshot.error!, onRetry: () => setState(_reload));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final sales = snapshot.data![0] as List<Sale>;
          final expenses = snapshot.data![1] as List<Expense>;
          final revenue = sales
              .where((sale) => sale.paymentMode != 'personal_use')
              .fold<double>(0, (total, sale) => total + sale.totalAmount);
          final personalUse = sales
              .where((sale) => sale.paymentMode == 'personal_use')
              .fold<double>(0, (total, sale) => total + sale.totalAmount);
          final settled = expenses
              .where((expense) => expense.status == 'settled')
              .fold<double>(0, (total, expense) => total + expense.amount);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Details(children: {
                if (widget.branchName != null) 'Branch': widget.branchName!,
                'Sales records': '${sales.length}',
                'Gross revenue': _money.format(revenue),
                'Personal use · not included in revenue':
                    _money.format(personalUse),
                'Settled expenses': _money.format(settled),
                'Pending expenses': _money.format(expenses
                    .where((expense) => expense.status == 'pending')
                    .fold<double>(
                        0, (total, expense) => total + expense.amount)),
                'Net operating result': _money.format(revenue - settled),
                if (widget.paymentMode != null ||
                    widget.orderType != null ||
                    widget.category != null)
                  'Sales filters':
                      '${widget.paymentMode ?? 'all payments'} · ${widget.orderType ?? 'all order types'} · ${widget.category ?? 'all categories'}',
                'Calculation':
                    'Net operating result = filtered gross sales − settled operating expenses.',
                'Expense scope':
                    'Expenses use the selected date and branch; sales payment, order-type and category filters do not change expenses.',
                'Note':
                    'Product costs are not tracked and are excluded, so this is not a full accounting net profit.',
              }),
              const SizedBox(height: 12),
              Text('Sales and personal-use records',
                  style: Theme.of(context).textTheme.titleLarge),
              ...sales.map((sale) => Card(
                    child: ListTile(
                      title: Text(
                          '${sale.pizzaName} · ${sale.sizeName} × ${sale.quantity}'),
                      subtitle: Text(
                          '${sale.branchName} · ${_date.format(sale.createdAt.toLocal())}'),
                      trailing: Text(_money.format(sale.totalAmount)),
                      onTap: () => _open(context, 'Sale transaction',
                          SaleDetailScreen(sale: sale)),
                    ),
                  )),
              const SizedBox(height: 12),
              Text('Expense records',
                  style: Theme.of(context).textTheme.titleLarge),
              ...expenses.map((expense) => Card(
                    child: ListTile(
                      title:
                          Text('${expense.financialHead} · ${expense.status}'),
                      subtitle: Text(
                          '${expense.branchName} · ${expense.description}'),
                      trailing: Text(_money.format(expense.amount)),
                      onTap: () => _open(context, 'Expense booking',
                          ExpenseDetailScreen(expense: expense)),
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}

class BranchManagementScreen extends StatefulWidget {
  const BranchManagementScreen({super.key});

  @override
  State<BranchManagementScreen> createState() => _BranchManagementScreenState();
}

class _BranchManagementScreenState extends State<BranchManagementScreen> {
  late Future<List<Branch>> _branches;
  final Map<String, Future<List<Map<String, dynamic>>>> _adminRequests = {};

  @override
  void initState() {
    super.initState();
    _branches = context.read<AppState>().branches();
  }

  Future<void> _addBranch() async {
    final name = TextEditingController();
    final address = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add branch'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Branch name')),
          const SizedBox(height: 12),
          TextField(
              controller: address,
              decoration: const InputDecoration(labelText: 'Address')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create')),
        ],
      ),
    );
    if (approved != true || !mounted) {
      name.dispose();
      address.dispose();
      return;
    }
    try {
      await context
          .read<AppState>()
          .createBranch(name.text.trim(), address.text.trim());
      if (mounted) {
        setState(() => _branches = context.read<AppState>().branches());
      }
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      name.dispose();
      address.dispose();
    }
  }

  Future<void> _addAdmin(Branch branch) async {
    final email = TextEditingController();
    final password = TextEditingController();
    final form = GlobalKey<FormState>();
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Admin access · ${branch.name}'),
        content: Form(
            key: form,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (value) => value != null &&
                          RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                              .hasMatch(value.trim())
                      ? null
                      : 'Enter a valid email address'),
              const SizedBox(height: 12),
              PasswordVisibilityField(
                controller: password,
                labelText: 'Temporary password (12+ characters)',
                validator: (value) => value != null && value.length < 12
                    ? 'Use at least 12 characters'
                    : null,
              ),
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Create admin')),
        ],
      ),
    );
    if (approved != true || !mounted) {
      email.dispose();
      password.dispose();
      return;
    }
    try {
      await context
          .read<AppState>()
          .createBranchAdmin(email.text.trim(), password.text, branch.id);
      if (mounted) {
        setState(() {
          _adminRequests[branch.id] =
              context.read<AppState>().branchAdmins(branchId: branch.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Branch admin created. Share credentials securely.')));
      }
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      email.dispose();
      password.dispose();
    }
  }

  Future<List<Map<String, dynamic>>> _adminsFor(Branch branch) =>
      _adminRequests.putIfAbsent(
        branch.id,
        () => context.read<AppState>().branchAdmins(branchId: branch.id),
      );

  Future<void> _editAdmin(
      Map<String, dynamic> admin, List<Branch> branches) async {
    final email = TextEditingController(text: admin['email'] as String);
    final password = TextEditingController();
    final form = GlobalKey<FormState>();
    var branchId = admin['branch_id'] as String;
    final updated = await showDialog<Map<String, String?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit branch admin'),
          content: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Login email'),
                    validator: (value) => value != null &&
                            RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                .hasMatch(value.trim())
                        ? null
                        : 'Enter a valid email address',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: branchId,
                    decoration: const InputDecoration(labelText: 'Branch'),
                    items: branches
                        .map((branch) => DropdownMenuItem(
                              value: branch.id,
                              child: Text(branch.name),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => branchId = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  PasswordVisibilityField(
                    controller: password,
                    labelText: 'New password (optional)',
                    helperText:
                        'Current passwords cannot be viewed. Leave blank to keep it, or enter a new password.',
                    validator: (value) =>
                        value != null && value.isNotEmpty && value.length < 12
                            ? 'Use at least 12 characters'
                            : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                Navigator.pop(dialogContext, {
                  'email': email.text.trim(),
                  'password': password.text,
                  'branchId': branchId,
                });
              },
              child: const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
    if (updated == null || !mounted) {
      email.dispose();
      password.dispose();
      return;
    }
    try {
      await context.read<AppState>().updateBranchAdmin(
            id: admin['id'] as String,
            email: updated['email']!,
            branchId: updated['branchId']!,
            password: updated['password'],
          );
      if (!mounted) return;
      setState(() {
        for (final branch in branches) {
          _adminRequests[branch.id] =
              context.read<AppState>().branchAdmins(branchId: branch.id);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Branch admin account updated.')),
      );
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      email.dispose();
      password.dispose();
    }
  }

  Future<void> _setAdminActive(
      Map<String, dynamic> admin, List<Branch> branches) async {
    final active = admin['active'] as bool? ?? true;
    final nextActive = !active;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title:
            Text(nextActive ? 'Enable branch admin?' : 'Disable branch admin?'),
        content: Text(nextActive
            ? '${admin['email']} will be able to sign in again.'
            : '${admin['email']} will lose access. Their sales, expenses and audit history will be retained.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(nextActive ? 'Enable account' : 'Disable account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<AppState>().setBranchAdminActive(
            id: admin['id'] as String,
            active: nextActive,
          );
      if (!mounted) return;
      setState(() {
        for (final branch in branches) {
          _adminRequests[branch.id] =
              context.read<AppState>().branchAdmins(branchId: branch.id);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(nextActive
              ? 'Branch admin account enabled.'
              : 'Branch admin account disabled.'),
        ),
      );
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Widget _branchAdminList(Branch branch, List<Branch> branches) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _adminsFor(branch),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorPanel(
              error: snapshot.error!,
              onRetry: () => setState(() {
                _adminRequests[branch.id] =
                    context.read<AppState>().branchAdmins(branchId: branch.id);
              }),
            );
          }
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return Column(
            children: [
              if (snapshot.data!.isEmpty)
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('No admin accounts registered'),
                ),
              ...snapshot.data!.map((admin) => ListTile(
                    leading: Icon(
                      admin['active'] == true
                          ? Icons.badge_outlined
                          : Icons.no_accounts_outlined,
                    ),
                    title: Text(admin['email'] as String),
                    subtitle: Text(
                      'Account ID: ${admin['id']} · ${admin['active'] == true ? 'Active' : 'Disabled'}',
                    ),
                    trailing: Wrap(
                      spacing: 0,
                      children: [
                        IconButton(
                          tooltip: 'Edit branch admin account',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _editAdmin(admin, branches),
                        ),
                        IconButton(
                          tooltip: admin['active'] == true
                              ? 'Disable branch admin'
                              : 'Enable branch admin',
                          icon: Icon(admin['active'] == true
                              ? Icons.person_off_outlined
                              : Icons.person_add_alt_1_outlined),
                          onPressed: () => _setAdminActive(admin, branches),
                        ),
                      ],
                    ),
                  )),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _addAdmin(branch),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Add branch admin'),
                ),
              ),
            ],
          );
        },
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Branches & access')),
        body: FutureBuilder<List<Branch>>(
          future: _branches,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorPanel(
                  error: snapshot.error!,
                  onRetry: () => setState(
                      () => _branches = context.read<AppState>().branches()));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return RefreshIndicator(
              onRefresh: () async => setState(() {
                _adminRequests.clear();
                _branches = context.read<AppState>().branches();
              }),
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                        'Branches are dynamically expandable. Admin accounts are restricted to one assigned branch.'),
                  ),
                  ...snapshot.data!.map((branch) => Card(
                        child: ExpansionTile(
                          leading:
                              const CircleAvatar(child: Icon(Icons.storefront)),
                          title: Text(branch.name),
                          subtitle: Text(branch.address ?? 'No address set'),
                          children: [
                            _branchAdminList(branch, snapshot.data!),
                          ],
                        ),
                      )),
                ],
              ),
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addBranch,
          icon: const Icon(Icons.add_business),
          label: const Text('Add branch'),
        ),
      );
}

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  late Future<List<Map<String, dynamic>>> _entries;

  @override
  void initState() {
    super.initState();
    _entries = context.read<AppState>().auditLog();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Audit history')),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _entries,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorPanel(
                  error: snapshot.error!,
                  onRetry: () => setState(
                      () => _entries = context.read<AppState>().auditLog()));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.data!.isEmpty) {
              return const Center(child: Text('No audit events recorded'));
            }
            return RefreshIndicator(
              onRefresh: () async => setState(
                  () => _entries = context.read<AppState>().auditLog()),
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: snapshot.data!.length,
                itemBuilder: (context, index) {
                  final entry = snapshot.data![index];
                  final details = entry['details'];
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.history)),
                      title: Text((entry['action'] as String? ?? 'event')
                          .replaceAll('.', ' ')),
                      subtitle: Text(
                          '${entry['branch_name'] ?? 'All branches'} · ${entry['actor_email'] ?? 'System'} · ${_date.format(DateTime.parse(entry['created_at'] as String).toLocal())}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(
                          context,
                          'Audit event',
                          _Details(children: {
                            'Action': entry['action']?.toString() ?? '',
                            'Entity':
                                '${entry['entity_type'] ?? ''} ${entry['entity_id'] ?? ''}',
                            'Branch': entry['branch_name']?.toString() ??
                                'All branches',
                            'Actor':
                                entry['actor_email']?.toString() ?? 'System',
                            'Details': details?.toString() ?? '{}',
                          })),
                    ),
                  );
                },
              ),
            );
          },
        ),
      );
}

class ExpenseDetailScreen extends StatelessWidget {
  const ExpenseDetailScreen({required this.expense, super.key});
  final Expense expense;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Expense booking')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _Details(children: {
            'Financial head': expense.financialHead,
            'Description': expense.description,
            'Amount': _money.format(expense.amount),
            'Status': expense.status,
            'Branch': expense.branchName,
            'Settlement': expense.settlementMode ?? 'Not settled',
            'Submitted': _date.format(expense.createdAt.toLocal()),
          }),
        ),
      );
}

class _Details extends StatelessWidget {
  const _Details({required this.children});
  final Map<String, String> children;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: children.entries
            .map((entry) => Card(
                  child: ListTile(
                    title: Text(entry.key),
                    subtitle: Text(
                      entry.value,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ))
            .toList(),
      );
}

class _BranchFinancialCard extends StatelessWidget {
  const _BranchFinancialCard({required this.branch, required this.onTap});

  final Map<String, dynamic> branch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget metric(String label, String key) => Text(
          '$label  ${_money.format(_number(branch[key]))}',
          style: const TextStyle(fontSize: 12),
        );

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      branch['branch_name'] as String,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  metric('Sales', 'revenue'),
                  metric('Expenses', 'expenses'),
                  metric('Net', 'net_profit'),
                  metric('Cash', 'cash_revenue'),
                  metric('Bank', 'bank_transfer_revenue'),
                  metric('Delivery', 'delivery_revenue'),
                  metric('Personal use', 'personal_use_amount'),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Tap to open this branch’s sales and expense records',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.onTap});
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: Theme.of(context).colorScheme.primary),
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ]),
          ),
        ),
      );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard(
      {required this.title, required this.action, required this.child});
  final String title;
  final Widget action;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              action
            ]),
            child,
          ]),
        ),
      );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 40),
            const SizedBox(height: 10),
            Text(error.toString(), textAlign: TextAlign.center),
            const SizedBox(height: 14),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ]),
        ),
      );
}

void _open(BuildContext context, String title, Widget screen) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) {
    if (screen is SalesScreen ||
        screen is ExpensesScreen ||
        screen is _Details) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: screen is _Details
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: screen,
              )
            : screen,
      );
    }
    return screen;
  }));
}

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(error.toString())));
}

double _number(dynamic value) => double.tryParse(value.toString()) ?? 0;

Widget _orderTotalRow(String label, String value, {bool bold = false}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(value,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
