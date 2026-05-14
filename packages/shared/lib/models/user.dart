class User {
  static const String managerRole = 'manager';
  static const String cashierRole = 'cashier';
  static const String presentationRole = 'presentation';

  final int? id;
  final String name;
  final String role; // manager | cashier, with old owner/admin normalized
  final String pin;
  final bool isActive;
  final bool hasFullAccess;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastLoginAt;
  final int? createdBy;
  final int? updatedBy;

  const User({
    this.id,
    required this.name,
    required this.role,
    required this.pin,
    this.isActive = true,
    this.hasFullAccess = false,
    this.createdAt,
    this.updatedAt,
    this.lastLoginAt,
    this.createdBy,
    this.updatedBy,
  });

  static String normalizeRole(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    switch (normalized) {
      case 'manager':
      case 'owner':
      case 'admin':
      case 'administrator':
        return managerRole;
      case 'viewer':
      case 'presentation':
        return presentationRole;
      case 'cashier':
        return cashierRole;
      default:
        return cashierRole;
    }
  }

  static String roleLabel(String? value) {
    switch (normalizeRole(value)) {
      case managerRole:
        return 'Manager';
      case presentationRole:
        return 'Presentation';
      default:
        return 'Cashier';
    }
  }

  String get normalizedRole => normalizeRole(role);

  bool get isManager => normalizedRole == managerRole;
  bool get isCashier => normalizedRole == cashierRole;

  /// Special login used for client demos / presentation privacy mode.
  /// This user can still run normal POS sales, but financial pages use a
  /// filtered presentation view instead of full real history.
  bool get isViewer => normalizedRole == presentationRole;
  bool get isPresentationLogin => isViewer;

  bool get hasManagementAccess => isManager || hasFullAccess;

  User copyWith({
    int? id,
    String? name,
    String? role,
    String? pin,
    bool? isActive,
    bool? hasFullAccess,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastLoginAt,
    int? createdBy,
    int? updatedBy,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      pin: pin ?? this.pin,
      isActive: isActive ?? this.isActive,
      hasFullAccess: hasFullAccess ?? this.hasFullAccess,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'role': role,
      'pin': pin,
      'is_active': isActive ? 1 : 0,
      'has_full_access': hasFullAccess ? 1 : 0,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'last_login_at': lastLoginAt?.toIso8601String(),
      'created_by': createdBy,
      'updated_by': updatedBy,
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      final text = value.toString().trim();
      if (text.isEmpty) return null;
      return DateTime.tryParse(text);
    }

    bool parseBool(dynamic value, {bool fallback = true}) {
      if (value == null) return fallback;
      if (value is bool) return value;
      if (value is num) return value.toInt() == 1;
      final text = value.toString().toLowerCase();
      return text == '1' || text == 'true';
    }

    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    return User(
      id: parseInt(map['id']),
      name: (map['name'] ?? '').toString(),
      role: (map['role'] ?? 'cashier').toString(),
      pin: (map['pin'] ?? '').toString(),
      isActive: parseBool(map['is_active'], fallback: true),
      hasFullAccess: parseBool(map['has_full_access'], fallback: false),
      createdAt: parseDate(map['created_at']),
      updatedAt: parseDate(map['updated_at']),
      lastLoginAt: parseDate(map['last_login_at']),
      createdBy: parseInt(map['created_by']),
      updatedBy: parseInt(map['updated_by']),
    );
  }
}
