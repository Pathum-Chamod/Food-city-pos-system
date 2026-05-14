class CustomerMonitorSummary {
  const CustomerMonitorSummary({
    required this.totalCustomers,
    required this.activeCustomers,
    required this.creditCustomers,
    required this.totalOutstanding,
    required this.overLimitCount,
    required this.loyaltyMembers,
    required this.totalLoyaltyPoints,
    required this.loyaltyLiability,
  });

  final int totalCustomers;
  final int activeCustomers;
  final int creditCustomers;
  final double totalOutstanding;
  final int overLimitCount;
  final int loyaltyMembers;
  final int totalLoyaltyPoints;
  final double loyaltyLiability;

  factory CustomerMonitorSummary.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return CustomerMonitorSummary(
      totalCustomers: _int(map['total_customers']),
      activeCustomers: _int(map['active_customers']),
      creditCustomers: _int(map['credit_customers']),
      totalOutstanding: _double(map['total_outstanding']),
      overLimitCount: _int(map['over_limit_count']),
      loyaltyMembers: _int(map['loyalty_members']),
      totalLoyaltyPoints: _int(map['total_loyalty_points']),
      loyaltyLiability: _double(map['loyalty_liability']),
    );
  }
}

class CustomerDashboard {
  const CustomerDashboard({
    required this.summary,
    required this.topOutstanding,
    required this.recentCustomers,
    required this.highLoyalty,
    required this.needsAttention,
  });

  final CustomerMonitorSummary summary;
  final List<CustomerMonitorRow> topOutstanding;
  final List<CustomerMonitorRow> recentCustomers;
  final List<CustomerMonitorRow> highLoyalty;
  final List<CustomerMonitorRow> needsAttention;

  factory CustomerDashboard.fromJson(Map<String, dynamic> json) {
    return CustomerDashboard(
      summary: CustomerMonitorSummary.fromJson(
        json['summary'] as Map<String, dynamic>?,
      ),
      topOutstanding: _rows(json['top_outstanding']),
      recentCustomers: _rows(json['recent_customers']),
      highLoyalty: _rows(json['high_loyalty']),
      needsAttention: _rows(json['needs_attention']),
    );
  }

  static List<CustomerMonitorRow> _rows(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(
          (item) =>
              CustomerMonitorRow.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }
}

class CustomerMonitorRow {
  const CustomerMonitorRow({
    required this.id,
    required this.customerCode,
    required this.name,
    required this.phone,
    required this.category,
    required this.pricingScheme,
    required this.creditBalance,
    required this.creditLimit,
    required this.creditStatus,
    required this.loyaltyPoints,
    required this.loyaltyValue,
    required this.lastPurchaseAt,
    required this.lastPaymentAt,
    required this.totalSpent,
    required this.purchaseCount,
    required this.healthLabel,
    required this.attentionReasons,
  });

  final int id;
  final String customerCode;
  final String name;
  final String phone;
  final String category;
  final String pricingScheme;
  final double creditBalance;
  final double creditLimit;
  final String creditStatus;
  final int loyaltyPoints;
  final double loyaltyValue;
  final String? lastPurchaseAt;
  final String? lastPaymentAt;
  final double totalSpent;
  final int purchaseCount;
  final String healthLabel;
  final List<String> attentionReasons;

  String get displayName {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final safePhone = phone.trim();
    return safePhone.isNotEmpty ? safePhone : customerCode;
  }

  bool get hasCreditBalance => creditBalance > 0.0001;
  bool get isOverLimit => creditLimit > 0 && creditBalance > creditLimit;
  bool get isBlocked => creditStatus.toLowerCase() == 'blocked';
  bool get isWatchlist => creditStatus.toLowerCase() == 'watchlist';

  factory CustomerMonitorRow.fromJson(Map<String, dynamic> json) {
    return CustomerMonitorRow(
      id: _int(json['id']),
      customerCode: _string(json['customer_code']),
      name: _string(json['name']),
      phone: _string(json['phone']),
      category: _string(json['category']),
      pricingScheme: _string(json['pricing_scheme']),
      creditBalance: _double(json['credit_balance']),
      creditLimit: _double(json['credit_limit']),
      creditStatus: _string(json['credit_status'], fallback: 'normal'),
      loyaltyPoints: _int(json['loyalty_points']),
      loyaltyValue: _double(json['loyalty_value']),
      lastPurchaseAt: _nullableString(json['last_purchase_at']),
      lastPaymentAt: _nullableString(json['last_payment_at']),
      totalSpent: _double(json['total_spent']),
      purchaseCount: _int(json['purchase_count']),
      healthLabel: _string(json['health_label'], fallback: 'Good Customer'),
      attentionReasons: _stringList(json['attention_reasons']),
    );
  }
}

class CustomerMonitorProfile {
  const CustomerMonitorProfile({
    required this.customer,
    required this.creditSummary,
    required this.loyaltySummary,
    required this.pricingSummary,
    required this.purchaseSummary,
    required this.recentTransactions,
    required this.recentCreditLedger,
    required this.recentLoyaltyLedger,
  });

  final CustomerMonitorRow customer;
  final Map<String, dynamic> creditSummary;
  final Map<String, dynamic> loyaltySummary;
  final Map<String, dynamic> pricingSummary;
  final Map<String, dynamic> purchaseSummary;
  final List<Map<String, dynamic>> recentTransactions;
  final List<Map<String, dynamic>> recentCreditLedger;
  final List<Map<String, dynamic>> recentLoyaltyLedger;

  factory CustomerMonitorProfile.fromJson(Map<String, dynamic> json) {
    return CustomerMonitorProfile(
      customer: CustomerMonitorRow.fromJson(
        Map<String, dynamic>.from(json['customer'] as Map? ?? const {}),
      ),
      creditSummary: _map(json['credit_summary']),
      loyaltySummary: _map(json['loyalty_summary']),
      pricingSummary: _map(json['pricing_summary']),
      purchaseSummary: _map(json['purchase_summary']),
      recentTransactions: _mapList(json['recent_transactions']),
      recentCreditLedger: _mapList(json['recent_credit_ledger']),
      recentLoyaltyLedger: _mapList(json['recent_loyalty_ledger']),
    );
  }
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse((value ?? '').toString()) ?? 0;
}

double _double(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse((value ?? '').toString()) ?? 0;
}

String _string(Object? value, {String fallback = ''}) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? fallback : text;
}

String? _nullableString(Object? value) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? null : text;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}
