import 'package:equatable/equatable.dart';

class UserSession extends Equatable {
  const UserSession({
    required this.userId,
    required this.employeeId,
    required this.businessId,
    required this.fullName,
    required this.position,
    required this.role,
    required this.businessName,
    this.mustChangePassword = false,
  });

  final String userId;
  final String? employeeId;
  final String? businessId;
  final String fullName;
  final String? position;
  final String role;
  final String businessName;
  final bool mustChangePassword;

  UserSession copyWith({bool? mustChangePassword}) {
    return UserSession(
      userId: userId,
      employeeId: employeeId,
      businessId: businessId,
      fullName: fullName,
      position: position,
      role: role,
      businessName: businessName,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
    );
  }

  @override
  List<Object?> get props => [
        userId,
        employeeId,
        businessId,
        fullName,
        position,
        role,
        businessName,
        mustChangePassword,
      ];
}
