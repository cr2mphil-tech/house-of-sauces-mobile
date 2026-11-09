import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'models.dart';

final _printDate = DateFormat('dd MMM yyyy, hh:mm a');

Future<void> printSalesOrder(Sale sale) async {
  final document = pw.Document();
  final personalUse = sale.paymentMode == 'personal_use';
  document.addPage(pw.Page(
    pageFormat: PdfPageFormat.roll80,
    margin: const pw.EdgeInsets.all(18),
    build: (context) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Center(
          child: pw.Column(children: [
            pw.Text('HOUSE OF SAUCES',
                style:
                    pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
            pw.Text(personalUse ? 'Personal-use record' : 'Sales order'),
          ]),
        ),
        pw.SizedBox(height: 16),
        _detail('Order', sale.orderGroupId.substring(0, 8).toUpperCase()),
        _detail('Date', _printDate.format(sale.createdAt.toLocal())),
        _detail('Branch', sale.branchName),
        if (sale.customerName != null) _detail('Customer', sale.customerName!),
        if (sale.customerPhone != null) _detail('Phone', sale.customerPhone!),
        pw.Divider(),
        pw.Text(sale.pizzaName,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        if (sale.productDescription.isNotEmpty)
          pw.Text(sale.productDescription),
        pw.Text('${sale.category} · ${sale.sizeName}'),
        _detail('Price × quantity',
            '${_amount(sale.unitPrice)} × ${sale.quantity}'),
        _detail('Order type', _label(sale.orderType)),
        _detail('Payment', _label(sale.paymentMode)),
        pw.Divider(),
        _detail('Items subtotal', _amount(sale.unitPrice * sale.quantity)),
        if (sale.deliveryFee > 0)
          _detail('Delivery fee', _amount(sale.deliveryFee)),
        _detail(
          personalUse ? 'Recorded value · not a sale' : 'TOTAL',
          _amount(sale.totalAmount),
          bold: true,
          fontSize: 14,
        ),
        pw.SizedBox(height: 16),
        pw.Center(child: pw.Text('Thank you for your order!')),
      ],
    ),
  ));
  await Printing.layoutPdf(
    onLayout: (_) async => document.save(),
    name: 'house-of-sauces-order-${sale.id.substring(0, 8)}.pdf',
  );
}

Future<void> printSalesOrderGroup(List<Sale> sales) async {
  if (sales.isEmpty) {
    throw ArgumentError.value(sales, 'sales', 'must not be empty');
  }
  final first = sales.first;
  final document = pw.Document();
  final subtotal = sales.fold<double>(
      0, (total, sale) => total + sale.unitPrice * sale.quantity);
  final deliveryFee =
      sales.fold<double>(0, (total, sale) => total + sale.deliveryFee);
  final total =
      sales.fold<double>(0, (amount, sale) => amount + sale.totalAmount);
  final personalUse = first.paymentMode == 'personal_use';
  document.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.roll80,
    margin: const pw.EdgeInsets.all(18),
    build: (_) => [
      pw.Center(
        child: pw.Column(children: [
          pw.Text('HOUSE OF SAUCES',
              style:
                  pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          pw.Text(personalUse ? 'Personal-use record' : 'Sales order'),
        ]),
      ),
      pw.SizedBox(height: 12),
      _detail('Order', first.orderGroupId.substring(0, 8).toUpperCase()),
      _detail('Date', _printDate.format(first.createdAt.toLocal())),
      _detail('Branch', first.branchName),
      if (first.customerName != null) _detail('Customer', first.customerName!),
      if (first.customerPhone != null) _detail('Phone', first.customerPhone!),
      _detail('Type', _label(first.orderType)),
      _detail('Payment', _label(first.paymentMode)),
      pw.Divider(),
      for (final sale in sales) ...[
        pw.Text('${sale.pizzaName} · ${sale.sizeName}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Text(
            '${_amount(sale.unitPrice)} × ${sale.quantity}  =  ${_amount(sale.unitPrice * sale.quantity)}'),
        pw.SizedBox(height: 6),
      ],
      pw.Divider(),
      _detail('Items subtotal', _amount(subtotal)),
      if (deliveryFee > 0) _detail('Delivery charges', _amount(deliveryFee)),
      _detail(
        personalUse ? 'Recorded value · not a sale' : 'TOTAL',
        _amount(total),
        bold: true,
        fontSize: 14,
      ),
      pw.SizedBox(height: 12),
      pw.Center(child: pw.Text('Thank you for your order!')),
    ],
  ));
  await Printing.layoutPdf(
    onLayout: (_) async => document.save(),
    name: 'house-of-sauces-order-${first.orderGroupId.substring(0, 8)}.pdf',
  );
}

Future<void> printSalesOrders(List<Sale> sales) async {
  final document = pw.Document();
  final businessSales =
      sales.where((sale) => sale.paymentMode != 'personal_use').toList();
  final personalUseSales =
      sales.where((sale) => sale.paymentMode == 'personal_use').toList();
  final businessOrderCount = businessSales
      .map((sale) => sale.orderGroupId.isEmpty ? sale.id : sale.orderGroupId)
      .toSet()
      .length;
  final personalUseOrderCount = personalUseSales
      .map((sale) => sale.orderGroupId.isEmpty ? sale.id : sale.orderGroupId)
      .toSet()
      .length;
  final total =
      businessSales.fold<double>(0, (sum, sale) => sum + sale.totalAmount);
  final personalUseTotal =
      personalUseSales.fold<double>(0, (sum, sale) => sum + sale.totalAmount);
  document.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    header: (_) => _reportHeader('Sales orders'),
    footer: _pageFooter,
    build: (_) => [
      pw.Text(
          'Business orders: $businessOrderCount  ·  Total sales: ${_amount(total)}'),
      if (personalUseOrderCount > 0)
        pw.Text(
            'Personal-use records: $personalUseOrderCount  ·  Value not counted as sales: ${_amount(personalUseTotal)}'),
      pw.SizedBox(height: 12),
      _table(
        const [
          'Date',
          'Branch',
          'Product',
          'Size',
          'Qty',
          'Type',
          'Payment',
          'Amount'
        ],
        sales
            .map((sale) => [
                  _printDate.format(sale.createdAt.toLocal()),
                  sale.branchName,
                  sale.productDescription.isEmpty
                      ? sale.pizzaName
                      : '${sale.pizzaName}\n${sale.productDescription}',
                  sale.sizeName,
                  '${sale.quantity}',
                  _label(sale.orderType),
                  _label(sale.paymentMode),
                  _amount(sale.totalAmount),
                ])
            .toList(),
        widths: const [1.35, 1, 1.4, 0.8, 0.45, 0.8, 1, 0.9],
      ),
    ],
  ));
  await Printing.layoutPdf(
    onLayout: (_) async => document.save(),
    name: 'house-of-sauces-sales-orders.pdf',
  );
}

Future<void> printOwnerReport({
  required Map<String, dynamic> summary,
  required List<Sale> sales,
  required List<Expense> expenses,
  required String period,
  required String branch,
  required List<String> filters,
  required List<Map<String, dynamic>> branchSummaries,
}) async {
  final document = pw.Document();
  final expensesTotal =
      expenses.fold<double>(0, (sum, expense) => sum + expense.amount);
  document.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    header: (_) => _reportHeader('Owner operating report'),
    footer: _pageFooter,
    build: (_) => [
      pw.Text('$period  ·  $branch'),
      if (filters.isNotEmpty) pw.Text('Sales filters: ${filters.join(' · ')}'),
      pw.Text('Generated ${_printDate.format(DateTime.now())}'),
      pw.SizedBox(height: 12),
      _table(
        const ['Metric', 'Amount / Count'],
        [
          ['Gross revenue', _amount(_number(summary['revenue']))],
          [
            'Delivery charges (included in gross revenue)',
            _amount(_number(summary['delivery_revenue']))
          ],
          ['Cash sales', _amount(_number(summary['cash_revenue']))],
          [
            'Bank transfer sales',
            _amount(_number(summary['bank_transfer_revenue']))
          ],
          [
            'Personal use (excluded from sales)',
            _amount(_number(summary['personal_use_amount']))
          ],
          ['Operating expenses', _amount(_number(summary['expenses']))],
          ['Net operating result', _amount(_number(summary['net_profit']))],
          ['Pending approvals', summary['pending_count'].toString()],
        ],
        widths: const [2, 1],
      ),
      if (branchSummaries.isNotEmpty) ...[
        pw.SizedBox(height: 18),
        pw.Text('Overall branch-wise breakup',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        _table(
          const [
            'Branch',
            'Filtered sales',
            'Personal use',
            'Delivery fees',
            'Settled expenses',
            'Net result'
          ],
          branchSummaries
              .map((item) => [
                    item['branch_name'] as String,
                    _amount(_number(item['revenue'])),
                    _amount(_number(item['personal_use_amount'])),
                    _amount(_number(item['delivery_revenue'])),
                    _amount(_number(item['expenses'])),
                    _amount(_number(item['net_profit'])),
                  ])
              .toList(),
          widths: const [1.2, 0.8, 0.8, 0.8, 0.8, 0.8],
        ),
      ],
      pw.SizedBox(height: 18),
      pw.Text('Sales (${sales.length})',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 6),
      _table(
        const [
          'Date',
          'Branch',
          'Product',
          'Size',
          'Qty',
          'Type',
          'Payment',
          'Amount'
        ],
        sales
            .map((sale) => [
                  _printDate.format(sale.createdAt.toLocal()),
                  sale.branchName,
                  sale.productDescription.isEmpty
                      ? sale.pizzaName
                      : '${sale.pizzaName}\n${sale.productDescription}',
                  sale.sizeName,
                  '${sale.quantity}',
                  _label(sale.orderType),
                  _label(sale.paymentMode),
                  _amount(sale.totalAmount),
                ])
            .toList(),
        widths: const [1.35, 1, 1.4, 0.8, 0.45, 0.8, 1, 0.9],
      ),
      pw.SizedBox(height: 18),
      pw.Text('Expenses (${expenses.length}) · ${_amount(expensesTotal)}',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      if (filters.isNotEmpty)
        pw.Text('Expenses include the full selected date and branch range.'),
      pw.SizedBox(height: 6),
      _table(
        const [
          'Date',
          'Branch',
          'Financial head',
          'Description',
          'Status',
          'Amount'
        ],
        expenses
            .map((expense) => [
                  _printDate.format(expense.createdAt.toLocal()),
                  expense.branchName,
                  expense.financialHead,
                  expense.description,
                  _label(expense.status),
                  _amount(expense.amount),
                ])
            .toList(),
        widths: const [1.2, 0.9, 1.2, 1.8, 0.8, 0.9],
      ),
    ],
  ));
  await Printing.layoutPdf(
    onLayout: (_) async => document.save(),
    name: 'house-of-sauces-owner-report.pdf',
  );
}

pw.Widget _reportHeader(String title) => pw.Container(
      alignment: pw.Alignment.centerLeft,
      margin: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('HOUSE OF SAUCES',
              style:
                  pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text(title, style: const pw.TextStyle(fontSize: 12)),
          pw.Divider(),
        ],
      ),
    );

pw.Widget _pageFooter(pw.Context context) => pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 10),
      child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 9)),
    );

pw.Widget _table(
  List<String> headers,
  List<List<String>> rows, {
  required List<double> widths,
}) =>
    pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: {
        for (var index = 0; index < widths.length; index++)
          index: pw.FlexColumnWidth(widths[index]),
      },
      children: [
        _tableRow(headers, header: true),
        ...rows.map(_tableRow),
      ],
    );

pw.TableRow _tableRow(List<String> values, {bool header = false}) =>
    pw.TableRow(
      decoration:
          header ? const pw.BoxDecoration(color: PdfColors.grey200) : null,
      children: values
          .map((value) => pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(value,
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight:
                          header ? pw.FontWeight.bold : pw.FontWeight.normal,
                    )),
              ))
          .toList(),
    );

pw.Widget _detail(String label, String value,
        {bool bold = false, double fontSize = 10}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
              child: pw.Text(label, style: pw.TextStyle(fontSize: fontSize))),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: fontSize,
                  fontWeight: bold ? pw.FontWeight.bold : null)),
        ],
      ),
    );

String _label(String value) => value
    .split('_')
    .map((word) =>
        word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}')
    .join(' ');

String _amount(double value) => 'Rs ${value.toStringAsFixed(2)}';

double _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.parse(value.toString());
}
