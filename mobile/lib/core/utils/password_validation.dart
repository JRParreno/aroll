class PasswordValidationResult {
  const PasswordValidationResult({
    required this.valid,
    required this.errors,
  });

  final bool valid;
  final List<String> errors;
}

const _minLength = 8;
final _hasUppercase = RegExp(r'[A-Z]');
final _hasSpecial = RegExp(r'''[!@#$%^&*(),.?":{}|<>_\-+=[\]\\;/'`~]''');

PasswordValidationResult validatePassword(String password) {
  final errors = <String>[];

  if (password.length < _minLength) {
    errors.add('At least 8 characters');
  }
  if (!_hasUppercase.hasMatch(password)) {
    errors.add('At least one uppercase letter');
  }
  if (!_hasSpecial.hasMatch(password)) {
    errors.add('At least one special character');
  }

  return PasswordValidationResult(
    valid: errors.isEmpty,
    errors: errors,
  );
}

bool passwordsMatch(String password, String confirmPassword) {
  return password.isNotEmpty && password == confirmPassword;
}
