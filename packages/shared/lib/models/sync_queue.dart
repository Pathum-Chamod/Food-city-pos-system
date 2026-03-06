class SyncQueueItem {
  final int? id;
  final String type; // e.g., 'SALE', 'INVENTORY_UPDATE'
  final String data; // JSON string of the payload
  final String status; // 'pending', 'synced', 'failed'
  final String createdAt;

  SyncQueueItem({
    this.id,
    required this.type,
    required this.data,
    this.status = 'pending',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'data': data,
      'status': status,
      'created_at': createdAt,
    };
  }
}
