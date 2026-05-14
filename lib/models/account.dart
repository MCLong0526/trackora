enum AccountType {
  // Asset accounts
  bank,
  eWallet,
  cash,
  investment,
  savings,
  crypto,
  forex,
  // Liability accounts
  creditCard,
  loan,
  mortgage,
  bnpl,
  otherLiability,
}

extension AccountTypeLabel on AccountType {
  bool get isLiability => const {
        AccountType.creditCard,
        AccountType.loan,
        AccountType.mortgage,
        AccountType.bnpl,
        AccountType.otherLiability,
      }.contains(this);

  String get namePlaceholder {
    switch (this) {
      case AccountType.investment:
        return 'e.g. Portfolio, ETF Account';
      case AccountType.savings:
        return 'e.g. High-Yield Savings';
      case AccountType.crypto:
        return 'e.g. BTC Wallet, ETH';
      case AccountType.forex:
        return 'e.g. USD Account';
      case AccountType.loan:
      case AccountType.mortgage:
      case AccountType.bnpl:
      case AccountType.otherLiability:
        return 'e.g. Car Loan, Home Loan';
      default:
        return 'e.g. My Wallet, Piggy Bank';
    }
  }

  String get label {
    switch (this) {
      case AccountType.bank:
        return 'Bank';
      case AccountType.eWallet:
        return 'E-Wallet';
      case AccountType.cash:
        return 'Cash';
      case AccountType.investment:
        return 'Investment';
      case AccountType.savings:
        return 'Savings';
      case AccountType.crypto:
        return 'Crypto';
      case AccountType.forex:
        return 'Forex';
      case AccountType.creditCard:
        return 'Credit Card';
      case AccountType.loan:
        return 'Loan';
      case AccountType.mortgage:
        return 'Mortgage';
      case AccountType.bnpl:
        return 'BNPL';
      case AccountType.otherLiability:
        return 'Other Debt';
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
      case AccountType.investment:
        return 'investment';
      case AccountType.savings:
        return 'savings';
      case AccountType.crypto:
        return 'crypto';
      case AccountType.forex:
        return 'forex';
      case AccountType.creditCard:
        return 'creditCard';
      case AccountType.loan:
        return 'loan';
      case AccountType.mortgage:
        return 'mortgage';
      case AccountType.bnpl:
        return 'bnpl';
      case AccountType.otherLiability:
        return 'otherLiability';
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
      case 'investment':
        return AccountType.investment;
      case 'savings':
        return AccountType.savings;
      case 'crypto':
        return AccountType.crypto;
      case 'forex':
        return AccountType.forex;
      case 'creditCard':
        return AccountType.creditCard;
      case 'loan':
        return AccountType.loan;
      case 'mortgage':
        return AccountType.mortgage;
      case 'bnpl':
        return AccountType.bnpl;
      case 'otherLiability':
        return AccountType.otherLiability;
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
