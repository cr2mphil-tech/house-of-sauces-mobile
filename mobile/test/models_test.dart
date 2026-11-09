import 'package:flutter_test/flutter_test.dart';
import 'package:house_of_sauces/models.dart';

void main() {
  test('parses menu prices returned by PostgreSQL as strings', () {
    final menu = MenuItem.fromJson({
      'id': 'menu-item-1',
      'name': 'Garden Pizza',
      'category': 'Vegetarian',
      'sizes': [
        {'id': 'size-1', 'name': 'Large', 'price': '1250.50'},
      ],
    });

    expect(menu.name, 'Garden Pizza');
    expect(menu.sizes.single.price, 1250.5);
  });

  test('parses role and branch claims for dashboard routing', () {
    final admin = AppUser.fromJson({
      'id': 'user-1',
      'email': 'branch@example.com',
      'role': 'branch_admin',
      'branchId': 'branch-1',
    });

    expect(admin.isOwner, isFalse);
    expect(admin.branchId, 'branch-1');
  });

  test('parses delivery fee separately from the order subtotal', () {
    final sale = Sale.fromJson({
      'id': 'sale-1',
      'pizza_name': 'Tikka',
      'category': "Regular Flavour's Pizzas",
      'size_name': 'Small',
      'quantity': 2,
      'unit_price': '450.00',
      'delivery_fee': '150.00',
      'total_amount': '1050.00',
      'order_type': 'delivery',
      'payment_mode': 'cash',
      'created_at': '2026-03-19T10:00:00.000Z',
      'branch_name': 'Main Branch',
      'order_group_id': 'order-group-1',
      'customer_name': 'Test Customer',
      'customer_phone': '+923001234567',
    });

    expect(sale.unitPrice * sale.quantity, 900);
    expect(sale.deliveryFee, 150);
    expect(sale.totalAmount, 1050);
    expect(sale.orderGroupId, 'order-group-1');
    expect(sale.customerName, 'Test Customer');
    expect(sale.customerPhone, '+923001234567');
  });
}
