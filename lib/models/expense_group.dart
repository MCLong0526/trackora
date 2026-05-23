class ExpenseGroup {
  final String id;
  final String name;
  final String createdBy;
  final List<GroupMember> members;
  final List<String> memberUids;
  final String currency;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ExpenseGroup({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.members,
    required this.memberUids,
    required this.currency,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ExpenseGroup.fromMap(Map<String, dynamic> data, {required String id}) {
    final rawMembers = data['members'] as List? ?? [];
    final members = rawMembers
        .whereType<Map>()
        .map((m) => GroupMember.fromMap(Map<String, dynamic>.from(m)))
        .toList();
    return ExpenseGroup(
      id: id,
      name: data['name'] as String? ?? '',
      createdBy: data['createdBy'] as String? ?? '',
      members: members,
      memberUids: List<String>.from(data['memberUids'] as List? ?? []),
      currency: data['currency'] as String? ?? 'USD',
      createdAt: readDate(data['createdAt']),
      updatedAt: readDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap({bool includeId = false}) {
    return {
      if (includeId) 'id': id,
      'name': name,
      'createdBy': createdBy,
      'members': members.map((m) => m.toMap()).toList(),
      'memberUids': memberUids,
      'currency': currency,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  ExpenseGroup copyWith({
    String? name,
    List<GroupMember>? members,
    List<String>? memberUids,
    DateTime? updatedAt,
  }) {
    return ExpenseGroup(
      id: id,
      name: name ?? this.name,
      createdBy: createdBy,
      members: members ?? this.members,
      memberUids: memberUids ?? this.memberUids,
      currency: currency,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime readDate(Object? value) {
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.parse(value);
    if (value != null) {
      try {
        final d = (value as dynamic).toDate();
        if (d is DateTime) return d;
      } catch (_) {}
    }
    return DateTime.now();
  }
}

class GroupMember {
  final String uid;
  final String displayName;
  final DateTime joinedAt;

  const GroupMember({
    required this.uid,
    required this.displayName,
    required this.joinedAt,
  });

  factory GroupMember.fromMap(Map<String, dynamic> data) {
    return GroupMember(
      uid: data['uid'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      joinedAt: ExpenseGroup.readDate(data['joinedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'displayName': displayName,
      'joinedAt': joinedAt.toIso8601String(),
    };
  }
}
