export type PasswordValidationResult = {
  valid: boolean;
  errors: string[];
};

const MIN_LENGTH = 8;
const HAS_UPPERCASE = /[A-Z]/;
const HAS_SPECIAL = /[!@#$%^&*(),.?":{}|<>_\-+=[\]\\;/'`~]/;

export function validatePassword(password: string): PasswordValidationResult {
  const errors: string[] = [];

  if (password.length < MIN_LENGTH) {
    errors.push("At least 8 characters");
  }
  if (!HAS_UPPERCASE.test(password)) {
    errors.push("At least one uppercase letter");
  }
  if (!HAS_SPECIAL.test(password)) {
    errors.push("At least one special character");
  }

  return { valid: errors.length === 0, errors };
}

export function passwordsMatch(
  password: string,
  confirmPassword: string
): boolean {
  return password.length > 0 && password === confirmPassword;
}

export function canSubmitPasswordChange(input: {
  currentPassword: string;
  newPassword: string;
  confirmPassword: string;
}): boolean {
  return (
    input.currentPassword.length > 0 &&
    validatePassword(input.newPassword).valid &&
    passwordsMatch(input.newPassword, input.confirmPassword)
  );
}
