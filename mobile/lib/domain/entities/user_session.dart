import 'package:equatable/equatable.dart';

class UserSession extends Equatable {
  const UserSession({
    required this.userId,
    required this.fullName,
    required this.role,
    required this.businessName,
    this.mustChangePassword = false,
  });

  final String userId;
  final String fullName;
  final String role;
  final String businessName;
  final bool mustChangePassword;

  @override
  List<Object?> get props =>
      [userId, fullName, role, businessName, mustChangePassword];
}
