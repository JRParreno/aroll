import 'package:flutter/material.dart';

class PasswordVisibilityToggle extends StatelessWidget {
  const PasswordVisibilityToggle({
    super.key,
    required this.visible,
    required this.onToggle,
  });

  final bool visible;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: visible ? 'Hide password' : 'Show password',
      onPressed: onToggle,
      icon: Icon(
        visible ? Icons.visibility_off : Icons.visibility,
      ),
    );
  }
}

InputDecoration passwordInputDecoration({
  required InputDecoration base,
  required bool visible,
  required VoidCallback onToggle,
}) {
  return base.copyWith(
    suffixIcon: PasswordVisibilityToggle(
      visible: visible,
      onToggle: onToggle,
    ),
  );
}
