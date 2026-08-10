/// Usuário da retaguarda (backoffice).
class RetaguardaUser {
  const RetaguardaUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    this.lastLoginAt,
    this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final String role; // superuser | admin
  final String status; // active | blocked
  final String? lastLoginAt;
  final String? createdAt;

  bool get isSuperuser => role == 'superuser';
  bool get isActive => status == 'active';

  factory RetaguardaUser.fromJson(Map<String, dynamic> json) => RetaguardaUser(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    role: json['role'] as String? ?? 'admin',
    status: json['status'] as String? ?? 'active',
    lastLoginAt: json['last_login_at'] as String?,
    createdAt: json['created_at'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'role': role,
    'status': status,
  };
}
