class Supplier {
  final int id;
  final String name;
  final String phone;

  const Supplier({
    required this.id,
    required this.name,
    required this.phone,
  });

  factory Supplier.fromMap(Map<String, dynamic> map) {
    return Supplier(
      id: int.tryParse(map['id'].toString()) ?? 0,
      name: map['name']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
    );
  }
}