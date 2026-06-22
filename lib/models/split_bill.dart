enum SplitMemberStatus { pending, paid, reminded }

enum SplitMode { equally, amount, percent, shares }

class SplitMember {
  final String id;
  final String name;
  final int colorIndex;
  final String? emoji;
  double amount;
  bool isPayer;
  SplitMemberStatus status;
  DateTime? paidAt;

  /// Linked contact (Person) id, set when the member is auto-saved to contacts.
  /// Lets the Contacts screen surface what this person owes across bills.
  String? personId;

  SplitMember({
    required this.id,
    required this.name,
    required this.colorIndex,
    this.emoji,
    required this.amount,
    this.isPayer = false,
    this.status = SplitMemberStatus.pending,
    this.paidAt,
    this.personId,
  });

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.length >= 2 ? name.substring(0, 2).toUpperCase() : name.toUpperCase();
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'colorIndex': colorIndex,
        'emoji': emoji,
        'amount': amount,
        'isPayer': isPayer,
        'status': status.name,
        'paidAt': paidAt?.toIso8601String(),
        if (personId != null) 'personId': personId,
      };

  factory SplitMember.fromMap(Map<String, dynamic> m) => SplitMember(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        colorIndex: (m['colorIndex'] as num?)?.toInt() ?? 0,
        emoji: m['emoji'] as String?,
        amount: (m['amount'] as num?)?.toDouble() ?? 0.0,
        isPayer: m['isPayer'] as bool? ?? false,
        status: SplitMemberStatus.values.firstWhere(
          (s) => s.name == m['status'],
          orElse: () => SplitMemberStatus.pending,
        ),
        paidAt: m['paidAt'] != null ? DateTime.tryParse(m['paidAt'] as String? ?? '') : null,
        personId: m['personId'] as String?,
      );

  SplitMember copyWith({
    String? name,
    double? amount,
    bool? isPayer,
    SplitMemberStatus? status,
    DateTime? paidAt,
    String? personId,
  }) =>
      SplitMember(
        id: id,
        name: name ?? this.name,
        colorIndex: colorIndex,
        emoji: emoji,
        amount: amount ?? this.amount,
        isPayer: isPayer ?? this.isPayer,
        status: status ?? this.status,
        paidAt: paidAt ?? this.paidAt,
        personId: personId ?? this.personId,
      );
}

/// A payment collected from a debtor against a split bill. Backed by a
/// "receive" expense ([expenseId]) — deleting that expense reverts the member
/// to owing again.
class SplitSettlement {
  final String memberId;
  final double amount;
  final String? accountId;
  final String expenseId;
  final DateTime date;

  const SplitSettlement({
    required this.memberId,
    required this.amount,
    this.accountId,
    required this.expenseId,
    required this.date,
  });

  Map<String, dynamic> toMap() => {
        'memberId': memberId,
        'amount': amount,
        if (accountId != null) 'accountId': accountId,
        'expenseId': expenseId,
        'date': date.toIso8601String(),
      };

  factory SplitSettlement.fromMap(Map<String, dynamic> m) => SplitSettlement(
        memberId: m['memberId'] as String? ?? '',
        amount: (m['amount'] as num?)?.toDouble() ?? 0.0,
        accountId: m['accountId'] as String?,
        expenseId: m['expenseId'] as String? ?? '',
        date: SplitBill._parseDate(m['date']),
      );
}

class SplitBill {
  final String id;
  final String expenseId;
  final String billNumber;
  final String title;
  final double totalAmount;
  final String currency;
  final String currencySymbol;
  final SplitMode splitMode;
  final List<SplitMember> members;
  final List<SplitSettlement> settlements;
  final DateTime date;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SplitBill({
    required this.id,
    required this.expenseId,
    required this.billNumber,
    required this.title,
    required this.totalAmount,
    required this.currency,
    required this.currencySymbol,
    required this.splitMode,
    required this.members,
    this.settlements = const [],
    required this.date,
    required this.createdAt,
    required this.updatedAt,
  });

  SplitMember get payer =>
      members.firstWhere((m) => m.isPayer, orElse: () => members.first);

  List<SplitMember> get debtors => members.where((m) => !m.isPayer).toList();

  /// Amount still owed by debtors (each member's [SplitMember.amount] tracks
  /// the remaining balance).
  double get outstanding => debtors
      .where((m) => m.status != SplitMemberStatus.paid)
      .fold(0, (s, m) => s + m.amount);

  /// Amount collected so far, summed from the recorded settlements (handles
  /// partial payments).
  double get collected =>
      settlements.fold(0.0, (s, x) => s + x.amount);

  bool get isClosed => debtors.every((m) => m.status == SplitMemberStatus.paid);

  Map<String, dynamic> toMap() => {
        'expenseId': expenseId,
        'billNumber': billNumber,
        'title': title,
        'totalAmount': totalAmount,
        'currency': currency,
        'currencySymbol': currencySymbol,
        'splitMode': splitMode.name,
        'members': members.map((m) => m.toMap()).toList(),
        'settlements': settlements.map((s) => s.toMap()).toList(),
        'date': date.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory SplitBill.fromMap(Map<String, dynamic> m, String id) => SplitBill(
        id: id,
        expenseId: m['expenseId'] as String? ?? '',
        billNumber: m['billNumber'] as String? ?? '',
        title: m['title'] as String? ?? '',
        totalAmount: (m['totalAmount'] as num?)?.toDouble() ?? 0.0,
        currency: m['currency'] as String? ?? 'MYR',
        currencySymbol: m['currencySymbol'] as String? ?? 'RM',
        splitMode: SplitMode.values.firstWhere(
          (s) => s.name == m['splitMode'],
          orElse: () => SplitMode.equally,
        ),
        members: (m['members'] as List<dynamic>? ?? [])
            .map((e) => SplitMember.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        settlements: (m['settlements'] as List<dynamic>? ?? [])
            .map((e) =>
                SplitSettlement.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        date: _parseDate(m['date']),
        createdAt: _parseDate(m['createdAt']),
        updatedAt: _parseDate(m['updatedAt']),
      );

  static DateTime _parseDate(Object? v) {
    if (v is String) {
      final d = DateTime.tryParse(v);
      if (d != null) return d;
    }
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  SplitBill copyWith({
    List<SplitMember>? members,
    List<SplitSettlement>? settlements,
    DateTime? updatedAt,
  }) =>
      SplitBill(
        id: id,
        expenseId: expenseId,
        billNumber: billNumber,
        title: title,
        totalAmount: totalAmount,
        currency: currency,
        currencySymbol: currencySymbol,
        splitMode: splitMode,
        members: members ?? this.members,
        settlements: settlements ?? this.settlements,
        date: date,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
