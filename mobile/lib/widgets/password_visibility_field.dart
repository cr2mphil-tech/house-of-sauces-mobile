import 'package:flutter/material.dart';

class PasswordVisibilityField extends StatefulWidget {
  const PasswordVisibilityField({
    required this.controller,
    required this.labelText,
    this.validator,
    this.helperText,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String labelText;
  final String? helperText;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordVisibilityField> createState() =>
      _PasswordVisibilityFieldState();
}

class _PasswordVisibilityFieldState extends State<PasswordVisibilityField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: widget.controller,
        obscureText: _obscureText,
        decoration: InputDecoration(
          labelText: widget.labelText,
          helperText: widget.helperText,
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            tooltip: _obscureText ? 'Show password' : 'Hide password',
            onPressed: () => setState(() => _obscureText = !_obscureText),
            icon: Icon(
              _obscureText
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
          ),
        ),
        validator: widget.validator,
        onFieldSubmitted: widget.onSubmitted,
      );
}
