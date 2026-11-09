import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'models.dart';

class AppState extends ChangeNotifier {
  final ApiClient _api = ApiClient();

  AppUser? user;
  bool restoring = true;
  String? selectedBranchId;
  String? sessionRestoreError;

  bool get isAuthenticated => user != null;

  Future<void> restoreSession() async {
    try {
      await _api.restoreToken();
      if (_api.hasToken) {
        final data = await _api.get('/auth/me') as Map<String, dynamic>;
        user = AppUser.fromJson(data);
        selectedBranchId = user?.branchId;
      }
    } catch (error) {
      if (error is ApiException) {
        await _api.clearToken();
      } else {
        sessionRestoreError = 'Could not restore the saved session: $error';
      }
    } finally {
      restoring = false;
      notifyListeners();
    }
  }

  Future<void> login(String email, String password) async {
    final data =
        await _api.post('/auth/login', {'email': email, 'password': password})
            as Map<String, dynamic>;
    await _api.storeToken(data['token'] as String);
    user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
    sessionRestoreError = null;
    selectedBranchId = user?.branchId;
    notifyListeners();
  }

  Future<void> logout() async {
    await _api.clearToken();
    user = null;
    selectedBranchId = null;
    notifyListeners();
  }

  Future<List<Branch>> branches() async {
    final rows = await _api.get('/branches') as List<dynamic>;
    return rows
        .map((row) => Branch.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> summary({
    String? from,
    String? to,
    String? paymentMode,
    String? orderType,
    String? category,
  }) async {
    final query = _query(from: from, to: to) ?? <String, String>{};
    if (paymentMode != null) query['paymentMode'] = paymentMode;
    if (orderType != null) query['orderType'] = orderType;
    if (category != null) query['category'] = category;
    return await _api.get(
      '/analytics/summary',
      query: query.isEmpty ? null : query,
    ) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> branchSummaries({
    String? from,
    String? to,
    String? branchId,
    String? paymentMode,
    String? orderType,
    String? category,
  }) async {
    final query = <String, String>{};
    if (from != null) query['from'] = from;
    if (to != null) query['to'] = to;
    if (branchId != null) query['branchId'] = branchId;
    if (paymentMode != null) query['paymentMode'] = paymentMode;
    if (orderType != null) query['orderType'] = orderType;
    if (category != null) query['category'] = category;
    final rows = await _api.get(
      '/analytics/branches',
      query: query.isEmpty ? null : query,
    ) as List<dynamic>;
    return rows.cast<Map<String, dynamic>>();
  }

  Future<List<Sale>> sales({
    String? from,
    String? to,
    String? menuSizeId,
    String? branchId,
    String? paymentMode,
    String? orderType,
    String? category,
  }) async {
    final query = _query(from: from, to: to) ?? <String, String>{};
    if (menuSizeId != null) query['menuSizeId'] = menuSizeId;
    if (branchId != null && user?.isOwner == true) query['branchId'] = branchId;
    if (paymentMode != null) query['paymentMode'] = paymentMode;
    if (orderType != null) query['orderType'] = orderType;
    if (category != null) query['category'] = category;
    final rows = await _api.get('/sales', query: query.isEmpty ? null : query)
        as List<dynamic>;
    return rows
        .map((row) => Sale.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<Expense>> expenses({
    String? from,
    String? to,
    String? branchId,
  }) async {
    final query = _query(from: from, to: to) ?? <String, String>{};
    if (branchId != null && user?.isOwner == true) {
      query['branchId'] = branchId;
    }
    final rows = await _api.get(
      '/expenses',
      query: query.isEmpty ? null : query,
    ) as List<dynamic>;
    return rows
        .map((row) => Expense.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<String>> expenseHeads() async {
    final rows = await _api.get('/expense-heads') as List<dynamic>;
    return rows.cast<String>();
  }

  Future<List<Map<String, dynamic>>> auditLog() async {
    final rows = await _api.get('/audit', query: _query()) as List<dynamic>;
    return rows.cast<Map<String, dynamic>>();
  }

  Future<List<MenuItem>> menu() async {
    final rows = await _api.get('/menu') as List<dynamic>;
    return rows
        .map((row) => MenuItem.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  void selectBranch(String? branchId) {
    selectedBranchId = branchId;
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> hotSelling({
    String? category,
    String? size,
    String? from,
    String? to,
  }) async {
    final query = <String, String>{};
    final branchId = user?.isOwner == true ? selectedBranchId : null;
    if (branchId != null) query['branchId'] = branchId;
    if (category != null) query['category'] = category;
    if (size != null) query['size'] = size;
    if (from != null) query['from'] = from;
    if (to != null) query['to'] = to;
    final rows =
        await _api.get('/analytics/hot-selling', query: query) as List<dynamic>;
    return rows.cast<Map<String, dynamic>>();
  }

  Future<void> recordSale({
    required List<Map<String, dynamic>> items,
    required String orderType,
    required String paymentMode,
    required double deliveryFee,
    String? customerName,
    String? customerPhone,
  }) async {
    final body = <String, dynamic>{
      'items': items,
      'orderType': orderType,
      'paymentMode': paymentMode,
      'deliveryFee': deliveryFee,
      if (customerName != null) 'customerName': customerName,
      if (customerPhone != null) 'customerPhone': customerPhone,
      if (user?.isOwner == true && selectedBranchId != null)
        'branchId': selectedBranchId,
    };
    await _api.post('/sales', body);
  }

  Future<void> updateMenuSizePrice({
    required String sizeId,
    required double price,
  }) async {
    await _api.patch('/menu/sizes/$sizeId', {'price': price});
  }

  Future<void> submitExpense({
    required String financialHead,
    required String description,
    required double amount,
  }) async {
    await _api.post('/expenses', {
      'financialHead': financialHead,
      'description': description,
      'amount': amount,
      if (user?.isOwner == true && selectedBranchId != null)
        'branchId': selectedBranchId,
    });
  }

  Future<void> settleExpense(String id, String settlementMode) async {
    await _api.post('/expenses/$id/settle', {'settlementMode': settlementMode});
  }

  Future<void> importMenu(List<Map<String, dynamic>> records) async {
    await _api.post('/menu/import', {'records': records});
  }

  Future<void> createMenuProduct({
    required String name,
    required String category,
    required String description,
    required List<Map<String, dynamic>> sizes,
  }) async {
    await _api.post('/menu', {
      'name': name,
      'category': category,
      'description': description,
      'sizes': sizes,
    });
  }

  Future<void> createBranch(String name, String address) async {
    await _api.post('/branches', {'name': name, 'address': address});
  }

  Future<void> createBranchAdmin(
      String email, String password, String branchId) async {
    await _api.post('/users', {
      'email': email,
      'password': password,
      'branchId': branchId,
    });
  }

  Future<List<Map<String, dynamic>>> branchAdmins({String? branchId}) async {
    final rows = await _api.get(
      '/users',
      query: branchId == null ? null : {'branchId': branchId},
    ) as List<dynamic>;
    return rows.cast<Map<String, dynamic>>();
  }

  Future<void> updateBranchAdmin({
    required String id,
    required String email,
    required String branchId,
    String? password,
  }) async {
    await _api.patch('/users/$id', {
      'email': email,
      'branchId': branchId,
      if (password != null && password.isNotEmpty) 'password': password,
    });
  }

  Future<void> setBranchAdminActive({
    required String id,
    required bool active,
  }) async {
    await _api.patch('/users/$id', {'active': active});
  }

  Map<String, String>? _query({String? from, String? to}) {
    final query = <String, String>{};
    if (user?.isOwner == true && selectedBranchId != null) {
      query['branchId'] = selectedBranchId!;
    }
    if (from != null) query['from'] = from;
    if (to != null) query['to'] = to;
    return query.isEmpty ? null : query;
  }
}
