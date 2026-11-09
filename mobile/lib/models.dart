class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.role,
    this.branchId,
  });

  final String id;
  final String email;
  final String role;
  final String? branchId;

  bool get isOwner => role == 'owner';

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        email: json['email'] as String,
        role: json['role'] as String,
        branchId: json['branchId'] as String?,
      );
}

class Branch {
  const Branch({required this.id, required this.name, this.address});

  final String id;
  final String name;
  final String? address;

  factory Branch.fromJson(Map<String, dynamic> json) => Branch(
        id: json['id'] as String,
        name: json['name'] as String,
        address: json['address'] as String?,
      );
}

class MenuSize {
  const MenuSize({required this.id, required this.name, required this.price});

  final String id;
  final String name;
  final double price;

  factory MenuSize.fromJson(Map<String, dynamic> json) => MenuSize(
        id: json['id'] as String,
        name: json['name'] as String,
        price: double.parse(json['price'].toString()),
      );
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    required this.category,
    required this.sizes,
    this.description = '',
  });

  final String id;
  final String name;
  final String category;
  final List<MenuSize> sizes;
  final String description;

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        description: (json['description'] ?? '') as String,
        sizes: (json['sizes'] as List<dynamic>)
            .map((item) => MenuSize.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

class Sale {
  const Sale({
    required this.id,
    required this.pizzaName,
    required this.category,
    this.productDescription = '',
    required this.sizeName,
    required this.quantity,
    required this.unitPrice,
    required this.deliveryFee,
    required this.totalAmount,
    required this.orderType,
    required this.paymentMode,
    required this.createdAt,
    this.branchName = '',
    this.orderGroupId = '',
    this.customerName,
    this.customerPhone,
  });

  final String id;
  final String pizzaName;
  final String category;
  final String productDescription;
  final String sizeName;
  final int quantity;
  final double unitPrice;
  final double deliveryFee;
  final double totalAmount;
  final String orderType;
  final String paymentMode;
  final DateTime createdAt;
  final String branchName;
  final String orderGroupId;
  final String? customerName;
  final String? customerPhone;

  factory Sale.fromJson(Map<String, dynamic> json) => Sale(
        id: json['id'] as String,
        pizzaName: (json['pizza_name'] ?? '') as String,
        category: (json['category'] ?? '') as String,
        productDescription: (json['description'] ?? '') as String,
        sizeName: (json['size_name'] ?? '') as String,
        quantity: int.parse(json['quantity'].toString()),
        unitPrice: double.parse(json['unit_price'].toString()),
        deliveryFee: double.parse(json['delivery_fee'].toString()),
        totalAmount: double.parse(json['total_amount'].toString()),
        orderType: json['order_type'] as String,
        paymentMode: json['payment_mode'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        branchName: (json['branch_name'] ?? '') as String,
        orderGroupId: (json['order_group_id'] ?? json['id']) as String,
        customerName: json['customer_name'] as String?,
        customerPhone: json['customer_phone'] as String?,
      );
}

class Expense {
  const Expense({
    required this.id,
    required this.financialHead,
    required this.description,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.branchName = '',
    this.settlementMode,
  });

  final String id;
  final String financialHead;
  final String description;
  final double amount;
  final String status;
  final DateTime createdAt;
  final String branchName;
  final String? settlementMode;

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'] as String,
        financialHead: json['financial_head'] as String,
        description: json['description'] as String,
        amount: double.parse(json['amount'].toString()),
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        branchName: (json['branch_name'] ?? '') as String,
        settlementMode: json['settlement_mode'] as String?,
      );
}
