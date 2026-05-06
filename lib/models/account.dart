enum AccountType { bank, eWallet, cash }

extension AccountTypeLabel on AccountType {
  String get label {
    switch (this) {
      case AccountType.bank:
        return 'Bank';
      case AccountType.eWallet:
        return 'E-Wallet';
      case AccountType.cash:
        return 'Cash';
    }
  }

  String get encode {
    switch (this) {
      case AccountType.bank:
        return 'bank';
      case AccountType.eWallet:
        return 'eWallet';
      case AccountType.cash:
        return 'cash';
    }
  }

  static AccountType decode(String? raw) {
    switch (raw) {
      case 'bank':
        return AccountType.bank;
      case 'eWallet':
        return AccountType.eWallet;
      case 'cash':
        return AccountType.cash;
      default:
        return AccountType.cash;
    }
  }
}

class Account {
  final String id;
  final String name;
  final AccountType type;
  final double openingBalance;
  final DateTime createdAt;

  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.openingBalance,
    required this.createdAt,
  });

  factory Account.fromMap(Map<String, dynamic> data, {required String id}) {
    return Account(
      id: id,
      name: data['name'] as String? ?? '',
      type: AccountTypeLabel.decode(data['type'] as String?),
      openingBalance: (data['openingBalance'] as num?)?.toDouble() ?? 0.0,
      createdAt: _readDate(data['createdAt']),
    );
  }

  Map<String, dynamic> toMap({bool includeId = false}) {
    return {
      if (includeId) 'id': id,
      'name': name,
      'type': type.encode,
      'openingBalance': openingBalance,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  Account copyWith({
    String? id,
    String? name,
    AccountType? type,
    double? openingBalance,
    DateTime? createdAt,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      openingBalance: openingBalance ?? this.openingBalance,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static DateTime _readDate(Object? value) {
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.parse(value);
    return DateTime.now();
  }
}
