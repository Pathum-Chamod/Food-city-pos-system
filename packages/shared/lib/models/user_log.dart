class UserLog {
  final int? id;
  final int? actorUserId;
  final String actorName;
  final String actionType;
  final int? targetUserId;
  final String? targetUserName;
  final String description;
  final DateTime? createdAt;

  const UserLog({
    this.id,
    this.actorUserId,
    required this.actorName,
    required this.actionType,
    this.targetUserId,
    this.targetUserName,
    required this.description,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'actor_user_id': actorUserId,
      'actor_name': actorName,
      'action_type': actionType,
      'target_user_id': targetUserId,
      'target_user_name': targetUserName,
      'description': description,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  factory UserLog.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      final text = value.toString().trim();
      if (text.isEmpty) return null;
      return DateTime.tryParse(text);
    }

    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    return UserLog(
      id: parseInt(map['id']),
      actorUserId: parseInt(map['actor_user_id']),
      actorName: (map['actor_name'] ?? '').toString(),
      actionType: (map['action_type'] ?? '').toString(),
      targetUserId: parseInt(map['target_user_id']),
      targetUserName: map['target_user_name']?.toString(),
      description: (map['description'] ?? '').toString(),
      createdAt: parseDate(map['created_at']),
    );
  }
}