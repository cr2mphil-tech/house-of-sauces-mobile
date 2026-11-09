import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;
import 'package:excel/excel.dart' as excel;

const menuExcelHeaders = [
  'Pizza Name',
  'Category',
  'Size',
  'Base Price',
  'Active',
  'Description',
];

Uint8List buildMenuTemplateBytes({
  required Iterable<String> categories,
  required Iterable<String> sizes,
}) {
  final workbook = excel.Excel.createExcel();
  workbook.rename('Sheet1', 'Menu Template');
  workbook.setDefaultSheet('Menu Template');
  final menuSheet = workbook['Menu Template'];
  final optionsSheet = workbook['Options'];

  final headerStyle = excel.CellStyle(
    bold: true,
    fontSize: 11,
    fontColorHex: excel.ExcelColor.white,
    backgroundColorHex: excel.ExcelColor.fromHexString('FFB63A27'),
  );
  for (var column = 0; column < menuExcelHeaders.length; column++) {
    final cell = menuSheet.cell(excel.CellIndex.indexByColumnRow(
      columnIndex: column,
      rowIndex: 0,
    ));
    cell.value = excel.TextCellValue(menuExcelHeaders[column]);
    cell.cellStyle = headerStyle;
  }
  menuSheet.setColumnWidth(0, 28);
  menuSheet.setColumnWidth(1, 22);
  menuSheet.setColumnWidth(2, 18);
  menuSheet.setColumnWidth(3, 18);
  menuSheet.setColumnWidth(4, 14);

  final optionValues = <String, List<String>>{
    'Category': _uniqueOptions(categories),
    'Size': _uniqueOptions(sizes),
    'Active': const ['true', 'false'],
  };
  final optionColumns = <String, int>{
    for (var i = 0; i < optionValues.keys.length; i++)
      optionValues.keys.elementAt(i): i,
  };
  for (final entry in optionValues.entries) {
    final column = optionColumns[entry.key]!;
    optionsSheet
        .cell(
            excel.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0))
        .value = excel.TextCellValue(entry.key);
    final values = entry.value.isEmpty ? const [''] : entry.value;
    for (var row = 0; row < values.length; row++) {
      optionsSheet
          .cell(excel.CellIndex.indexByColumnRow(
              columnIndex: column, rowIndex: row + 1))
          .value = excel.TextCellValue(values[row]);
    }
  }

  final instructions = workbook['Instructions'];
  const guidance = [
    'House of Sauces menu import template',
    'Fill in one row for each product size or bundle. Keep the header names unchanged.',
    'Required: Pizza Name, Category, Size, Base Price.',
    'Active is optional; use true or false. A blank value defaults to true.',
    'Description is optional and can contain deal contents or product notes.',
    'Choose existing categories and sizes from the dropdown, or type a new value.',
    'Base Price must be a positive number. Do not merge cells or add a title above the headers.',
    'Save this workbook as .xlsx, then use Import XLSX in the app.',
  ];
  for (var row = 0; row < guidance.length; row++) {
    instructions
        .cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = excel.TextCellValue(guidance[row]);
  }
  instructions.setColumnWidth(0, 105);

  final encoded = workbook.encode();
  if (encoded == null || encoded.isEmpty) {
    throw StateError('Could not generate the Excel menu template.');
  }

  return _addTemplateValidations(
    Uint8List.fromList(encoded),
    optionColumns,
    optionValues,
  );
}

List<String> _uniqueOptions(Iterable<String> values) {
  final unique = <String>{};
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) unique.add(trimmed);
  }
  return unique.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

Uint8List _addTemplateValidations(
  Uint8List bytes,
  Map<String, int> optionColumns,
  Map<String, List<String>> optionValues,
) {
  final files = archive.ZipDecoder().decodeBytes(bytes);
  final workbookFile = files.findFile('xl/workbook.xml');
  final relationshipsFile = files.findFile('xl/_rels/workbook.xml.rels');
  if (workbookFile == null || relationshipsFile == null) {
    throw StateError('Could not prepare Excel dropdown lists.');
  }

  var workbookXml = utf8.decode(workbookFile.content as List<int>);
  final relationshipsXml = utf8.decode(relationshipsFile.content as List<int>);
  final optionsSheetPath = _sheetPath(workbookXml, relationshipsXml, 'Options');
  final menuSheetPath =
      _sheetPath(workbookXml, relationshipsXml, 'Menu Template');
  final menuSheetFile = files.findFile(menuSheetPath);
  if (menuSheetFile == null || files.findFile(optionsSheetPath) == null) {
    throw StateError('Could not locate the Excel template worksheets.');
  }

  workbookXml = _hideSheet(workbookXml, 'Options');
  workbookXml = _addNamedRanges(workbookXml, optionColumns, optionValues);
  _replaceArchiveFile(files, 'xl/workbook.xml', utf8.encode(workbookXml));

  final menuXml = utf8.decode(menuSheetFile.content as List<int>);
  final patchedMenuXml = _addMenuValidations(menuXml);
  _replaceArchiveFile(files, menuSheetPath, utf8.encode(patchedMenuXml));

  final encoded = archive.ZipEncoder().encode(files);
  if (encoded == null || encoded.isEmpty) {
    throw StateError('Could not finish generating the Excel menu template.');
  }
  return Uint8List.fromList(encoded);
}

String _sheetPath(
    String workbookXml, String relationshipsXml, String sheetName) {
  final sheet = RegExp(r'<sheet\b[^>]*/?>')
      .allMatches(workbookXml)
      .map((match) => match.group(0)!)
      .firstWhere(
        (tag) => _xmlAttribute(tag, 'name') == sheetName,
        orElse: () => '',
      );
  final relationshipId = _xmlAttribute(sheet, 'r:id');
  if (relationshipId == null) {
    throw StateError('Excel template is missing the "$sheetName" worksheet.');
  }

  final relationship = RegExp(r'<Relationship\b[^>]*/?>')
      .allMatches(relationshipsXml)
      .map((match) => match.group(0)!)
      .firstWhere(
        (tag) => _xmlAttribute(tag, 'Id') == relationshipId,
        orElse: () => '',
      );
  final target = _xmlAttribute(relationship, 'Target');
  if (target == null) {
    throw StateError(
        'Could not find the "$sheetName" worksheet in the workbook.');
  }
  return target.startsWith('/') ? target.substring(1) : 'xl/$target';
}

String? _xmlAttribute(String tag, String name) {
  final attribute =
      RegExp('\\b${RegExp.escape(name)}="([^"]*)"').firstMatch(tag);
  return attribute?.group(1);
}

String _hideSheet(String workbookXml, String name) {
  final sheetTag = RegExp(r'<sheet\b[^>]*/?>')
      .allMatches(workbookXml)
      .firstWhere(
        (match) => _xmlAttribute(match.group(0)!, 'name') == name,
        orElse: () =>
            throw StateError('Could not hide the Excel dropdown worksheet.'),
      );
  final tag = sheetTag.group(0)!;
  final hiddenTag = tag
      .replaceFirst(
        RegExp(r'\sstate="[^"]*"'),
        '',
      )
      .replaceFirst(RegExp(r'\s*/?>$'), ' state="hidden"/>');
  return workbookXml.replaceRange(sheetTag.start, sheetTag.end, hiddenTag);
}

String _addNamedRanges(
  String workbookXml,
  Map<String, int> optionColumns,
  Map<String, List<String>> optionValues,
) {
  const columnLetters = ['A', 'B', 'C'];
  final names = optionColumns.entries.map((entry) {
    final column = columnLetters[entry.value];
    final lastRow = (optionValues[entry.key]!.length + 1).clamp(2, 5001);
    return '<definedName name="${entry.key}Options">\'Options\'!\$$column\$2:\$$column\$$lastRow</definedName>';
  }).join();
  final definedNames = '<definedNames>$names</definedNames>';
  if (workbookXml.contains('</definedNames>')) {
    return workbookXml.replaceFirst('</definedNames>', '$names</definedNames>');
  }
  return workbookXml.replaceFirst('</sheets>', '</sheets>$definedNames');
}

String _addMenuValidations(String sheetXml) {
  const validations = '''
<dataValidations count="4">
<dataValidation type="list" allowBlank="1" showErrorMessage="0" sqref="B2:B5001"><formula1>CategoryOptions</formula1></dataValidation>
<dataValidation type="list" allowBlank="1" showErrorMessage="0" sqref="C2:C5001"><formula1>SizeOptions</formula1></dataValidation>
<dataValidation type="decimal" operator="greaterThan" allowBlank="1" showErrorMessage="1" errorStyle="stop" errorTitle="Invalid price" error="Enter a price greater than zero." sqref="D2:D5001"><formula1>0</formula1></dataValidation>
<dataValidation type="list" allowBlank="1" showErrorMessage="0" sqref="E2:E5001"><formula1>ActiveOptions</formula1></dataValidation>
</dataValidations>
''';
  if (!sheetXml.contains('</sheetData>')) {
    throw StateError('Could not prepare the Excel menu worksheet.');
  }
  return sheetXml.replaceFirst('</sheetData>', '</sheetData>$validations');
}

void _replaceArchiveFile(archive.Archive files, String path, List<int> bytes) {
  files.addFile(archive.ArchiveFile(path, bytes.length, bytes));
}

List<Map<String, dynamic>> parseMenuWorkbook(Uint8List bytes) {
  if (bytes.isEmpty) {
    throw const FormatException(
        'The selected Excel file is empty. Choose a valid .xlsx workbook.');
  }
  if (bytes.length > 10 * 1024 * 1024) {
    throw const FormatException(
        'The Excel file is over the 10 MB import limit.');
  }
  if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4b) {
    throw const FormatException(
      'This file is not a valid .xlsx workbook. Download the menu template and save it as an Excel Workbook (.xlsx).',
    );
  }

  late final excel.Excel workbook;
  try {
    workbook = excel.Excel.decodeBytes(bytes);
  } on UnsupportedError {
    throw const FormatException(
      'This file could not be opened as an .xlsx workbook. Download a fresh menu template and try again.',
    );
  } on FormatException {
    throw const FormatException(
      'This Excel workbook is damaged or incomplete. Download a fresh menu template and try again.',
    );
  } catch (error) {
    throw FormatException(
      'This Excel workbook could not be read. Download the menu template and try again. Details: $error',
    );
  }

  late final Map<String, excel.Sheet> sheets;
  try {
    sheets = workbook.tables;
    if (sheets.isEmpty) {
      throw const FormatException('Workbook has no worksheet.');
    }
  } catch (error) {
    throw FormatException(
      'This Excel workbook has no readable worksheet. Download the menu template and try again. Details: $error',
    );
  }
  String cellText(List<excel.Data?> row, int column) =>
      column < row.length ? row[column]?.value?.toString().trim() ?? '' : '';

  final records = <Map<String, dynamic>>[];
  final recordsByKey = <String, Map<String, dynamic>>{};
  const specialPizzas = {
    'crown kababish',
    '4 in 1 pizza',
    'stuff kababish',
    'lava pizza',
  };
  for (final entry in sheets.entries) {
    final rows = entry.value.rows;
    for (var headerRow = 0; headerRow < rows.length; headerRow++) {
      final headers = rows[headerRow]
          .map((cell) => _menuHeader(cell?.value?.toString() ?? ''))
          .toList();
      int? findHeader(Iterable<String> aliases) {
        for (final alias in aliases) {
          final index = headers.indexOf(alias);
          if (index >= 0) return index;
        }
        return null;
      }

      final dealNameColumn = findHeader(['deal number']);
      final nameColumn = findHeader(
          ['pizza name', 'product name', 'item name', 'name', 'flavour name']);
      final categoryColumn = findHeader(['category']);
      final sizeColumn =
          findHeader(['size', 'size portion', 'size description']);
      final priceColumn = findHeader([
        'base price',
        'base price rs',
        'price',
        'price rs',
        'unit price rs'
      ]);
      final descriptionColumn =
          findHeader(['description', 'deal contents', 'contents']);
      final activeColumn = findHeader(['active']);
      final isDealTable = dealNameColumn != null && priceColumn != null;
      final selectedNameColumn = isDealTable ? dealNameColumn : nameColumn;
      final isSpecialItemTable =
          categoryColumn == null && headers.contains('size description');
      final isOtherProductTable = categoryColumn != null &&
          nameColumn != null &&
          headers[nameColumn] == 'item name' &&
          sizeColumn != null;
      if (selectedNameColumn == null ||
          sizeColumn == null && !isDealTable ||
          priceColumn == null ||
          categoryColumn == null && !isDealTable && sizeColumn == null) {
        continue;
      }

      for (var index = headerRow + 1; index < rows.length; index++) {
        final row = rows[index];
        final rowHeaders = row
            .map((cell) => _menuHeader(cell?.value?.toString() ?? ''))
            .toSet();
        if (rowHeaders.contains('category') &&
                rowHeaders.contains('item name') ||
            rowHeaders.contains('deal number') &&
                rowHeaders.contains('deal contents')) {
          continue;
        }
        final name = cellText(row, selectedNameColumn);
        if (isDealTable &&
            !RegExp(r'^DEAL\s*\d+', caseSensitive: false).hasMatch(name)) {
          continue;
        }
        final rawPrice = cellText(row, priceColumn)
            .replaceAll(',', '')
            .replaceAll(RegExp(r'^(Rs\.?|PKR)\s*', caseSensitive: false), '');
        final size = isDealTable ? 'Bundle' : cellText(row, sizeColumn!);
        final category = isDealTable
            ? 'Deals'
            : categoryColumn == null
                ? ''
                : cellText(row, categoryColumn);
        final description =
            descriptionColumn == null ? '' : cellText(row, descriptionColumn);
        if (name.isEmpty &&
            category.isEmpty &&
            size.isEmpty &&
            rawPrice.isEmpty &&
            description.isEmpty) {
          continue;
        }
        if (name.isEmpty &&
            size.isEmpty &&
            rawPrice.isEmpty &&
            description.isEmpty) {
          continue;
        }
        if (name.toLowerCase() == 'total' ||
            name.toLowerCase() == 'grand total') {
          continue;
        }
        final price = double.tryParse(rawPrice);
        if ((isDealTable ||
                isSpecialItemTable ||
                isOtherProductTable ||
                categoryColumn == null) &&
            (name.isEmpty || size.isEmpty || price == null || price <= 0)) {
          continue;
        }
        final resolvedCategory = category.isNotEmpty
            ? category
            : isDealTable
                ? 'Deals'
                : name.toLowerCase() == '1 miter pizza'
                    ? 'Special Item (Single Offer)'
                    : specialPizzas.contains(name.toLowerCase())
                        ? "Special Flavour's Pizzas"
                        : "Regular Flavour's Pizzas";
        if (isSpecialItemTable &&
            recordsByKey.keys.any((key) => key.startsWith(
                '${resolvedCategory.toLowerCase()}\u0000${name.toLowerCase()}\u0000'))) {
          continue;
        }
        if (name.isEmpty || size.isEmpty || price == null || price <= 0) {
          throw FormatException(
            'Invalid product data on spreadsheet row ${index + 1} of "${entry.key}". Enter a product name, size and positive price.',
          );
        }
        final activeText = activeColumn == null
            ? 'true'
            : cellText(row, activeColumn).toLowerCase();
        final record = <String, dynamic>{
          'name': name,
          'category': resolvedCategory,
          'description': description,
          'size': size,
          'price': price,
          'active': !{'false', 'no', '0'}.contains(activeText),
        };
        final key =
            '${resolvedCategory.toLowerCase()}\u0000${name.toLowerCase()}\u0000${size.toLowerCase()}';
        final existing = recordsByKey[key];
        if (existing != null) {
          if (existing['price'] != price) {
            throw FormatException(
              'Conflicting prices for "$name" ($size) in the workbook. Keep one authoritative price row.',
            );
          }
          if ((existing['description'] as String).isEmpty &&
              description.isNotEmpty) {
            existing['description'] = description;
          }
          continue;
        }
        recordsByKey[key] = record;
        if (recordsByKey.length > 5000) {
          throw const FormatException(
              'A maximum of 5,000 menu rows can be imported at once.');
        }
      }
    }
  }
  records.addAll(recordsByKey.values);
  if (records.isEmpty) {
    throw const FormatException(
      'No supported menu tables were found. Include columns for product name, category, size and price, or use the supplied workbook structure.',
    );
  }
  return records;
}

String _menuHeader(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[().]'), '')
    .replaceAll('/', ' ')
    .replaceAll(RegExp(r'\s+'), ' ');
