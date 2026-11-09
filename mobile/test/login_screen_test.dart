import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:house_of_sauces/screens.dart';
import 'package:house_of_sauces/widgets/password_visibility_field.dart';

import 'package:house_of_sauces/app_state.dart';

void main() {
  testWidgets('login screen validates empty credentials', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    expect(find.text('House of Sauces'), findsOneWidget);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
  });

  testWidgets('login password can be shown and hidden', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    final passwordField = find.descendant(
      of: find.byType(PasswordVisibilityField),
      matching: find.byType(TextFormField),
    );
    final editablePassword = find.descendant(
      of: passwordField,
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editablePassword).obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(tester.widget<EditableText>(editablePassword).obscureText, isFalse);
    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(tester.widget<EditableText>(editablePassword).obscureText, isTrue);
  });

  testWidgets('branch admin password can be shown and hidden', (tester) async {
    final password = TextEditingController();
    addTearDown(password.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PasswordVisibilityField(
          controller: password,
          labelText: 'Temporary password (12+ characters)',
        ),
      ),
    ));

    final passwordField = find.byType(TextFormField);
    final editablePassword = find.descendant(
      of: passwordField,
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editablePassword).obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(tester.widget<EditableText>(editablePassword).obscureText, isFalse);
    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(tester.widget<EditableText>(editablePassword).obscureText, isTrue);
  });
}
