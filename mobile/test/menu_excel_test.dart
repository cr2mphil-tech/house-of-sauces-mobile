import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as excel;
import 'package:flutter_test/flutter_test.dart';
import 'package:house_of_sauces/menu_excel.dart';

void main() {
  test('template matches import columns and provides menu dropdowns', () {
    final bytes = buildMenuTemplateBytes(
      categories: ['Classic', 'Signature'],
      sizes: ['Regular', 'Large'],
    );
    final workbook = excel.Excel.decodeBytes(bytes);
    final menu = workbook.tables['Menu Template']!;
    final headers =
        menu.rows.first.map((cell) => cell?.value.toString()).toList();

    expect(headers, menuExcelHeaders);
    expect(workbook.tables.keys.first, 'Menu Template');

    final archive = ZipDecoder().decodeBytes(bytes);
    final workbookXml =
        utf8.decode(archive.findFile('xl/workbook.xml')!.content as List<int>);
    final menuXml = utf8.decode(
        archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
    expect(workbookXml, contains('name="CategoryOptions"'));
    expect(workbookXml, contains("'Options'!\$A\$2:\$A\$3"));
    expect(workbookXml, contains('name="SizeOptions"'));
    expect(workbookXml, contains('name="Options"'));
    expect(workbookXml, contains('state="hidden"'));
    expect(menuXml, contains('<formula1>CategoryOptions</formula1>'));
    expect(menuXml, contains('<formula1>SizeOptions</formula1>'));
    expect(menuXml, contains('<formula1>ActiveOptions</formula1>'));
    expect(menuXml, contains('sqref="D2:D5001"'));
    final options = workbook.tables['Options']!;
    expect(options.rows[1][0]?.value.toString(), 'Classic');
    expect(options.rows[2][0]?.value.toString(), 'Signature');
    expect(options.rows[1][1]?.value.toString(), 'Large');
    expect(options.rows[2][1]?.value.toString(), 'Regular');
  });

  test('imports menu rows using the template column names', () {
    final workbook = excel.Excel.createExcel();
    final sheet = workbook['Sheet1'];
    const headers = ['Pizza Name', 'Category', 'Size', 'Base Price', 'Active'];
    const values = ['Garden Pizza', 'Vegetarian', 'Large', 1250.5, 'false'];
    for (var column = 0; column < headers.length; column++) {
      sheet
          .cell(excel.CellIndex.indexByColumnRow(
              columnIndex: column, rowIndex: 0))
          .value = excel.TextCellValue(headers[column]);
      sheet
          .cell(excel.CellIndex.indexByColumnRow(
              columnIndex: column, rowIndex: 1))
          .value = switch (values[column]) {
        final String value => excel.TextCellValue(value),
        final num value => excel.DoubleCellValue(value.toDouble()),
        _ => throw StateError('Unexpected test value'),
      };
    }

    final records = parseMenuWorkbook(Uint8List.fromList(workbook.encode()!));
    expect(records, [
      {
        'name': 'Garden Pizza',
        'category': 'Vegetarian',
        'description': '',
        'size': 'Large',
        'price': 1250.5,
        'active': false,
      },
    ]);
  });

  test('imports reference prices, deal contents and generic products', () {
    final workbook = excel.Excel.createExcel();
    final reference = workbook['Pizza Menu Reference'];
    const referenceRows = [
      ['Pizza Name', 'Size', 'Price (Rs.)'],
      ['Tikka', 'Small', 450],
      ['Crown Kababish', 'Medium', 1100],
      ['1 Miter Pizza', 'Jumbo', 3000],
    ];
    for (var row = 0; row < referenceRows.length; row++) {
      for (var column = 0; column < referenceRows[row].length; column++) {
        final value = referenceRows[row][column];
        reference
                .cell(excel.CellIndex.indexByColumnRow(
                    columnIndex: column, rowIndex: row))
                .value =
            value is num
                ? excel.DoubleCellValue(value.toDouble())
                : excel.TextCellValue(value.toString());
      }
    }

    final products = workbook['Sheet2'];
    const productRows = [
      ['Deal Number', 'Deal Contents', 'Price (Rs.)'],
      ['DEAL 01', '2 Small Pizzas + 1.5L Drink', 1299],
      ['Category', 'Item Name', 'Size / Portion', 'Price (Rs.)'],
      ['Pasta', 'Creamy Pasta', 'Half', 550],
    ];
    for (var row = 0; row < productRows.length; row++) {
      for (var column = 0; column < productRows[row].length; column++) {
        final value = productRows[row][column];
        products
                .cell(excel.CellIndex.indexByColumnRow(
                    columnIndex: column, rowIndex: row))
                .value =
            value is num
                ? excel.DoubleCellValue(value.toDouble())
                : excel.TextCellValue(value.toString());
      }
    }

    final records = parseMenuWorkbook(Uint8List.fromList(workbook.encode()!));
    expect(records, [
      {
        'name': 'Tikka',
        'category': "Regular Flavour's Pizzas",
        'description': '',
        'size': 'Small',
        'price': 450.0,
        'active': true,
      },
      {
        'name': 'Crown Kababish',
        'category': "Special Flavour's Pizzas",
        'description': '',
        'size': 'Medium',
        'price': 1100.0,
        'active': true,
      },
      {
        'name': '1 Miter Pizza',
        'category': 'Special Item (Single Offer)',
        'description': '',
        'size': 'Jumbo',
        'price': 3000.0,
        'active': true,
      },
      {
        'name': 'DEAL 01',
        'category': 'Deals',
        'description': '2 Small Pizzas + 1.5L Drink',
        'size': 'Bundle',
        'price': 1299.0,
        'active': true,
      },
      {
        'name': 'Creamy Pasta',
        'category': 'Pasta',
        'description': '',
        'size': 'Half',
        'price': 550.0,
        'active': true,
      },
    ]);
  });

  test('template remains valid before any menu categories exist', () {
    final bytes = buildMenuTemplateBytes(categories: [], sizes: []);
    final workbook = excel.Excel.decodeBytes(bytes);
    final options = workbook.tables['Options']!;

    expect(options.rows[1][0]?.value.toString(), '');
    expect(options.rows[1][1]?.value.toString(), '');

    final archive = ZipDecoder().decodeBytes(bytes);
    final workbookXml =
        utf8.decode(archive.findFile('xl/workbook.xml')!.content as List<int>);
    expect(workbookXml, contains("'Options'!\$A\$2:\$A\$2"));
    expect(workbookXml, contains("'Options'!\$B\$2:\$B\$2"));
  });

  test('reports unsupported or damaged files with template guidance', () {
    expect(
      () => parseMenuWorkbook(Uint8List.fromList([1, 2, 3, 4])),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Download the menu template'),
        ),
      ),
    );
  });
}
