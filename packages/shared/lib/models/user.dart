class User {
  final int? id;
  final String name;
  final String role; // 'manager' or 'cashier'
  final String pin;

  User({
    this.id,
    required this.name,
    required this.role,
    required this.pin,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'role': role,
      'pin': pin,
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'],
      name: map['name'],
      role: map['role'],
      pin: map['pin'],
    );
  }
}
