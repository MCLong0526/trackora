class TravelGroup {
  final String id;
  final String name;
  final String currency;
  final DateTime startDate;
  final DateTime? endDate;
  final String ownerId;
  final List<String> memberIds;
  final String? inviteCode;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TravelGroup({
    required this.id,
    required this.name,
    required this.currency,
    required this.startDate,
    this.endDate,
    required this.ownerId,
    required this.memberIds,
    this.inviteCode,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TravelGroup.fromMap(Map<String, dynamic> data, {required String id}) {
    return TravelGroup(
      id: id,
      name: data['name'] as String,
      currency: data['currency'] as String? ?? 'USD',
      startDate: readDate(data['startDate']),
      endDate: data['endDate'] != null ? readDate(data['endDate']) : null,
      ownerId: data['ownerId'] as String,
      memberIds: List<String>.from(data['memberIds'] as List? ?? []),
      inviteCode: data['inviteCode'] as String?,
      createdAt: readDate(data['createdAt']),
      updatedAt: readDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap({bool includeId = false}) {
    return {
      if (includeId) 'id': id,
      'name': name,
      'currency': currency,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'ownerId': ownerId,
      'memberIds': memberIds,
      if (inviteCode != null) 'inviteCode': inviteCode,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  TravelGroup copyWith({
    String? id,
    String? name,
    String? currency,
    DateTime? startDate,
    Object? endDate = _sentinel,
    String? ownerId,
    List<String>? memberIds,
    Object? inviteCode = _sentinel,
    DateTime? updatedAt,
  }) {
    return TravelGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      currency: currency ?? this.currency,
      startDate: startDate ?? this.startDate,
      endDate: identical(endDate, _sentinel) ? this.endDate : endDate as DateTime?,
      ownerId: ownerId ?? this.ownerId,
      memberIds: memberIds ?? this.memberIds,
      inviteCode: identical(inviteCode, _sentinel) ? this.inviteCode : inviteCode as String?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static const _sentinel = Object();

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
    throw FormatException('Unsupported date value: $value');
  }
}

enum MemberStatus { active, invited }

class TravelGroupMember {
  final String id;
  final String name;
  final String? userId;
  final String? email;
  final MemberStatus status;
  final DateTime createdAt;

  const TravelGroupMember({
    required this.id,
    required this.name,
    this.userId,
    this.email,
    required this.status,
    required this.createdAt,
  });

  factory TravelGroupMember.fromMap(
    Map<String, dynamic> data, {
    required String id,
  }) {
    return TravelGroupMember(
      id: id,
      name: data['name'] as String,
      userId: data['userId'] as String?,
      email: data['email'] as String?,
      status: data['status'] == 'invited'
          ? MemberStatus.invited
          : MemberStatus.active,
      createdAt: TravelGroup.readDate(data['createdAt']),
    );
  }

  Map<String, dynamic> toMap({bool includeId = false}) {
    return {
      if (includeId) 'id': id,
      'name': name,
      'userId': userId,
      'email': email,
      'status': status == MemberStatus.invited ? 'invited' : 'active',
      'createdAt': createdAt.toIso8601String(),
    };
  }

  TravelGroupMember copyWith({
    String? name,
    Object? userId = _sentinel,
    Object? email = _sentinel,
    MemberStatus? status,
  }) {
    return TravelGroupMember(
      id: id,
      name: name ?? this.name,
      userId: identical(userId, _sentinel) ? this.userId : userId as String?,
      email: identical(email, _sentinel) ? this.email : email as String?,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }

  static const _sentinel = Object();
}
