enum PersonType { friend, coworker, family, other }

extension PersonTypeX on PersonType {
  String get label {
    switch (this) {
      case PersonType.friend:
        return 'Friend';
      case PersonType.coworker:
        return 'Coworker';
      case PersonType.family:
        return 'Family';
      case PersonType.other:
        return 'Other';
    }
  }

  String get encoded {
    switch (this) {
      case PersonType.friend:
        return 'friend';
      case PersonType.coworker:
        return 'coworker';
      case PersonType.family:
        return 'family';
      case PersonType.other:
        return 'other';
    }
  }

  static PersonType decode(String? raw) {
    switch (raw) {
      case 'friend':
        return PersonType.friend;
      case 'coworker':
        return PersonType.coworker;
      case 'family':
        return PersonType.family;
      default:
        return PersonType.other;
    }
  }
}

class Person {
  final String id;
  final String name;
  final PersonType type;
  final String? phone;
  final String? note;
  final int colorIndex;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Person({
    required this.id,
    required this.name,
    required this.type,
    this.phone,
    this.note,
    this.colorIndex = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  factory Person.fromMap(Map<String, dynamic> data, {required String id}) {
    return Person(
      id: id,
      name: data['name'] as String? ?? '',
      type: PersonTypeX.decode(data['type'] as String?),
      phone: data['phone'] as String?,
      note: data['note'] as String?,
      colorIndex: (data['colorIndex'] as int?) ?? 0,
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap({bool includeId = false}) => {
        if (includeId) 'id': id,
        'name': name,
        'type': type.encoded,
        'phone': phone,
        'note': note,
        'colorIndex': colorIndex,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static const _sentinel = Object();

  Person copyWith({
    String? id,
    String? name,
    PersonType? type,
    Object? phone = _sentinel,
    Object? note = _sentinel,
    int? colorIndex,
    DateTime? updatedAt,
  }) {
    return Person(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      phone: identical(phone, _sentinel) ? this.phone : phone as String?,
      note: identical(note, _sentinel) ? this.note : note as String?,
      colorIndex: colorIndex ?? this.colorIndex,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime _readDate(Object? value) {
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.parse(value);
    if (value != null) {
      try {
        final date = (value as dynamic).toDate();
        if (date is DateTime) return date;
      } catch (_) {}
    }
    throw FormatException('Unsupported date value: $value');
  }
}
