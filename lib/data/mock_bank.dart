import '../app/clock.dart';
import 'models.dart';

/// "Now" for the app: the system clock (tests pin it via [clock]).
DateTime get demoToday => clock();

/// The mock history was written around 5 Nov 2026 (the signed-off screens).
/// It is moved by whole months to the current month, so day-of-month patterns
/// ("paid on the 5th") still hold and "this month so far" always has data.
const _anchorYear = 2026, _anchorMonth = 11;
int _monthShift = 0;
DateTime _today = DateTime(_anchorYear, _anchorMonth, 5);

/// Demo logins for the two mock customers. Test values only.
/// A demo sign-in. The customer can log in with their [username] ("priya.sharma")
/// or their mobile number, written as digits only, with or without the 91 country
/// code ("9876500001" or "919876500001"). Login IDs never contain spaces or "+".
class DemoLogin {
  final String username;
  final String mobile; // 10 digits, no country code
  final String mpin;
  final String customerId;
  final String label;

  const DemoLogin(this.username, this.mobile, this.mpin, this.customerId, this.label);

  /// The mobile number as a login ID: country code and number, digits only.
  String get mobileLogin => '91$mobile';

  bool matches(String loginId) {
    final id = loginId.trim().toLowerCase();
    return id == username || id == mobile || id == mobileLogin;
  }
}

const demoLogins = [
  DemoLogin('priya.sharma', '9876500001', '1111', 'CUST-1001', 'Priya Sharma · Salaried'),
  DemoLogin('rajesh.iyer', '9876500002', '2222', 'CUST-2001', 'Rajesh Iyer · Business'),
];

/// Illustrative product catalogue. Real rates come from the bank's rate engine.
const productCatalogue = [
  ProductOffer(
    code: 'SWEEP_FD',
    name: 'Auto-sweep FD',
    tagline: 'Earns more, stays accessible',
    rate: 7.10,
    kind: ProductKind.deposit,
    defaultTenureMonths: 12,
  ),
  ProductOffer(
    code: 'FD_1Y',
    name: 'Fixed Deposit · 1 year',
    tagline: 'Lock in a known return',
    rate: 7.25,
    kind: ProductKind.deposit,
    defaultTenureMonths: 12,
  ),
  ProductOffer(
    code: 'RD',
    name: 'Recurring Deposit',
    tagline: 'Built from salary',
    rate: 6.90,
    kind: ProductKind.deposit,
    defaultTenureMonths: 24,
  ),
  ProductOffer(
    code: 'BIZ_OD',
    name: 'Business overdraft',
    tagline: 'Draw only what you need, pay interest on what you use',
    rate: 11.50,
    kind: ProductKind.credit,
    defaultTenureMonths: 12,
  ),
  ProductOffer(
    code: 'WC_LOAN',
    name: 'Working capital loan',
    tagline: 'Fixed EMIs to fund stock and receivables',
    rate: 12.25,
    kind: ProductKind.credit,
    defaultTenureMonths: 12,
  ),
  ProductOffer(
    code: 'BIZ_LOAN',
    name: 'Business loan · 3 years',
    tagline: 'For expansion and equipment',
    rate: 14.00,
    kind: ProductKind.credit,
    defaultTenureMonths: 36,
  ),
];

ProductOffer product(String code) => productCatalogue.firstWhere((p) => p.code == code);

/// Stands in for the bank's APIs (CBS, CRM, BBPS, OCV). Returns canned data.
class MockBankApi {
  /// [loginId] is a username or a digits-only mobile number (see [DemoLogin.matches]).
  DemoLogin? authenticate(String loginId, String mpin) {
    for (final login in demoLogins) {
      if (login.matches(loginId) && login.mpin == mpin.trim()) return login;
    }
    return null;
  }

  Future<CustomerData> loadCustomer(String customerId) async {
    final now = demoToday;
    _today = DateTime(now.year, now.month, now.day);
    _monthShift = (now.year * 12 + now.month) - (_anchorYear * 12 + _anchorMonth);
    return switch (customerId) {
      'CUST-1001' => _priya(),
      'CUST-2001' => _rajesh(),
      _ => throw ArgumentError('Unknown customer $customerId'),
    };
  }
}

class _Txns {
  final String accountId;
  final Map<String, Merchant> merchants;
  final List<Transaction> list = [];
  int _seq = 0;

  _Txns(this.accountId, this.merchants);

  void debit(DateTime d, double amount, String description,
      {String? payee, String? merchant, String? category, String channel = 'UPI'}) {
    _add(TransactionType.debit, d, amount, description, payee, merchant, category, channel);
  }

  void credit(DateTime d, double amount, String description,
      {String? payee, String category = 'Income', String channel = 'NEFT'}) {
    _add(TransactionType.credit, d, amount, description, payee, null, category, channel);
  }

  void spend(DateTime d, String merchantId, double amount) {
    final m = merchants[merchantId]!;
    debit(d, amount, m.merchantName, merchant: merchantId, category: m.category);
  }

  void _add(TransactionType type, DateTime d, double amount, String description, String? payee,
      String? merchant, String? category, String channel) {
    if (d.isAfter(_today)) return; // early in the month, later "this month" spends have not happened yet
    _seq++;
    list.add(Transaction(
      transactionId: '$accountId-T${_seq.toString().padLeft(4, '0')}',
      accountId: accountId,
      transactionType: type,
      amount: amount,
      transactionTimestamp: DateTime(d.year, d.month, d.day, 10 + (_seq % 9), (_seq * 7) % 60),
      description: description,
      channel: channel,
      category: category ?? 'Other',
      merchantId: merchant,
      payeeId: payee,
    ));
  }
}

DateTime _d(int y, int m, int d) => DateTime(y, m + _monthShift, d);

// ---------------------------------------------------------------------------
// Priya Sharma: salaried, surplus balance -> deposit recommendation
// ---------------------------------------------------------------------------
CustomerData _priya() {
  const id = 'CUST-1001';
  const acc = 'ACC-P-01';
  const merchants = [
    Merchant('M_SWIGGY', 'Swiggy', 'Food'),
    Merchant('M_ZOMATO', 'Zomato', 'Food'),
    Merchant('M_COASTAL', 'Coastal Kitchen', 'Food'),
    Merchant('M_MYNTRA', 'Myntra', 'Shopping'),
    Merchant('M_AMAZON', 'Amazon', 'Shopping'),
    Merchant('M_UBER', 'Uber', 'Travel'),
    Merchant('M_INDIGO', 'IndiGo', 'Travel'),
    Merchant('M_IRCTC', 'IRCTC', 'Travel'),
    Merchant('M_APOLLO', 'Apollo Pharmacy', 'Health'),
    Merchant('M_BMS', 'BookMyShow', 'Entertainment'),
    Merchant('M_SALON', 'Trends Salon', 'Personal care'),
    Merchant('M_POWER', 'Electricity bill', 'Bills'),
    Merchant('M_FIBRE', 'ACT Fibernet', 'Bills'),
    Merchant('M_OTT', 'Netflix', 'Bills'),
    Merchant('M_TERM', 'Term insurance premium', 'Bills'),
  ];
  const payees = [
    Payee('P_SALARY', 'Ventura Tech Pvt Ltd', PayeeKind.employer),
    Payee('P_AMMA', 'Amma', PayeeKind.person),
    Payee('P_AIRTEL', 'Airtel postpaid', PayeeKind.biller),
    Payee('P_CARD', 'Credit card bill', PayeeKind.card),
  ];
  final t = _Txns(acc, {for (final m in merchants) m.merchantId: m});

  // Salary on the 1st, March to November.
  for (var m = 3; m <= 11; m++) {
    t.credit(_d(2026, m, 1), 85000, 'SALARY VENTURA TECH', payee: 'P_SALARY', category: 'Salary');
  }
  // Airtel on the 5th for 8 months, and the monthly transfer to Amma (1st to 5th).
  const ammaDays = [3, 2, 4, 1, 3, 5, 2, 4];
  const cardBills = <double>[11200.0, 9850.0, 13400.0, 10750.0, 12100.0, 11600.0, 12980.0, 11320.0];
  for (var i = 0; i < 8; i++) {
    final month = 3 + i;
    t.debit(_d(2026, month, 5), 799, 'AIRTEL POSTPAID', payee: 'P_AIRTEL', category: 'Bills', channel: 'BBPS');
    t.debit(_d(2026, month, ammaDays[i]), 15000, 'UPI TO AMMA', payee: 'P_AMMA', category: 'Transfers');
    t.debit(_d(2026, month, 8), cardBills[i], 'CREDIT CARD PAYMENT', payee: 'P_CARD', category: 'Card payment');
  }

  // Food, Aug to Oct (mostly Saturdays), for the monthly average behind the cap.
  const augSat = [8, 15, 22, 29], augAmt = <double>[2000.0, 1900, 2100, 1800];
  const sepSat = [5, 12, 19, 26], sepAmt = <double>[2000.0, 2100, 2000, 2000];
  for (var i = 0; i < 4; i++) {
    t.spend(_d(2026, 8, augSat[i]), i.isEven ? 'M_SWIGGY' : 'M_COASTAL', augAmt[i]);
    t.spend(_d(2026, 9, sepSat[i]), i.isEven ? 'M_ZOMATO' : 'M_COASTAL', sepAmt[i]);
  }
  // October: first five days, then the rest of the month.
  t.spend(_d(2026, 10, 3), 'M_SWIGGY', 2600);
  t.spend(_d(2026, 10, 4), 'M_COASTAL', 1600);
  t.spend(_d(2026, 10, 2), 'M_POWER', 2300);
  t.spend(_d(2026, 10, 2), 'M_FIBRE', 1200);
  t.spend(_d(2026, 10, 3), 'M_OTT', 649);
  t.spend(_d(2026, 10, 4), 'M_TERM', 6751);
  t.spend(_d(2026, 10, 2), 'M_UBER', 1600);
  t.spend(_d(2026, 10, 5), 'M_IRCTC', 8000);
  t.spend(_d(2026, 10, 4), 'M_AMAZON', 9501);
  t.spend(_d(2026, 10, 3), 'M_APOLLO', 2500);
  t.spend(_d(2026, 10, 4), 'M_BMS', 2300);
  t.spend(_d(2026, 10, 5), 'M_SALON', 2000);
  t.spend(_d(2026, 10, 10), 'M_COASTAL', 1500);
  t.spend(_d(2026, 10, 17), 'M_SWIGGY', 1100);
  t.spend(_d(2026, 10, 24), 'M_ZOMATO', 900);
  t.spend(_d(2026, 10, 31), 'M_SWIGGY', 600);
  t.spend(_d(2026, 10, 14), 'M_MYNTRA', 4200);
  t.spend(_d(2026, 10, 21), 'M_UBER', 2300);

  // November so far (1st is a Sunday).
  t.spend(_d(2026, 11, 1), 'M_COASTAL', 5400);
  t.spend(_d(2026, 11, 1), 'M_SWIGGY', 3200);
  t.spend(_d(2026, 11, 2), 'M_ZOMATO', 1400);
  t.spend(_d(2026, 11, 3), 'M_SWIGGY', 1600);
  t.spend(_d(2026, 11, 4), 'M_ZOMATO', 2600);
  t.spend(_d(2026, 11, 2), 'M_POWER', 2350);
  t.spend(_d(2026, 11, 2), 'M_FIBRE', 1200);
  t.spend(_d(2026, 11, 3), 'M_OTT', 649);
  t.spend(_d(2026, 11, 4), 'M_TERM', 6851);
  t.spend(_d(2026, 11, 3), 'M_UBER', 1400);
  t.spend(_d(2026, 11, 4), 'M_INDIGO', 6000);
  t.spend(_d(2026, 11, 2), 'M_MYNTRA', 5300);
  t.spend(_d(2026, 11, 3), 'M_APOLLO', 3200);
  t.spend(_d(2026, 11, 4), 'M_SALON', 2170);
  t.spend(_d(2026, 11, 1), 'M_BMS', 3500);

  // End-of-day balances: above ₹1.5 lakh for the last 41 days, a dip before that.
  final balances = <DailyBalance>[];
  for (var i = 0; i < 60; i++) {
    final day = DateTime(demoToday.year, demoToday.month, demoToday.day - i);
    final double value;
    if (i == 0) {
      value = 185000;
    } else if (i <= 40) {
      value = 158000 + ((i * 7919) % 38000).toDouble();
    } else if (i == 41) {
      value = 98000;
    } else {
      value = 82000 + ((i * 3517) % 30000).toDouble();
    }
    balances.add(DailyBalance(acc, day, value));
  }

  return CustomerData(
    customer: Customer(
      customerId: id,
      customerType: 'INDIVIDUAL',
      firstName: 'Priya',
      lastName: 'Sharma',
      dateOfBirth: _d(1993, 7, 14),
      customerSince: _d(2019, 4, 2),
      status: 'ACTIVE',
    ),
    profile: CustomerProfile(
      customerId: id,
      occupation: 'Software engineer',
      annualIncome: 1020000,
      preferredLanguage: 'English',
      riskCategory: 'MODERATE',
      creditScore: 781,
      creditBureau: 'CIBIL',
      scoreDate: _d(2026, 10, 15),
    ),
    employment: const EmploymentDetails(
      customerId: id,
      employmentType: 'SALARIED',
      employerName: 'Ventura Tech Pvt Ltd',
      monthlyIncome: 85000,
    ),
    persona: Persona(
      customerId: id,
      personaType: PersonaType.salaryCustomer,
      assignedOn: _d(2026, 10, 31),
      assignedBy: 'OCV persona model v1',
    ),
    accounts: const [
      DepositAccount(
        accountId: acc,
        customerId: id,
        accountType: AccountType.savings,
        accountNumber: '50210045671234',
        currentBalance: 185000,
        availableBalance: 185000,
      ),
    ],
    fixedDeposits: const [],
    loans: const [],
    payees: payees,
    merchants: merchants,
    transactions: t.list,
    dailyBalances: balances,
    billsDue: [
      BillDue('P_AIRTEL', 799, _d(2026, 11, 7)),
      BillDue('P_CARD', 12430, _d(2026, 11, 9), usuallyPaidInFull: true),
    ],
    expectedInflows: const [],
  );
}

// ---------------------------------------------------------------------------
// Rajesh Iyer: sole proprietor, lumpy cash flow -> credit recommendation
// ---------------------------------------------------------------------------
CustomerData _rajesh() {
  const id = 'CUST-2001';
  const acc = 'ACC-R-01';
  const merchants = [
    Merchant('M_VRL', 'VRL Logistics', 'Logistics'),
    Merchant('M_DTDC', 'DTDC Courier', 'Logistics'),
    Merchant('M_PACK', 'Pack Pro Supplies', 'Packaging'),
    Merchant('M_PHONE', 'Broadband and phone', 'Utilities'),
  ];
  const payees = [
    Payee('R_PAYROLL', 'Staff salaries', PayeeKind.payroll),
    Payee('R_SHARMA', 'Sharma Yarns', PayeeKind.vendor),
    Payee('R_KAVERI', 'Kaveri Dyes', PayeeKind.vendor),
    Payee('R_TNEB', 'TNEB electricity', PayeeKind.biller),
    Payee('R_GST', 'GST payment', PayeeKind.statutory),
    Payee('R_RENT', 'Shop rent', PayeeKind.landlord),
    Payee('R_BUYERS', 'Customer receipts', PayeeKind.person),
  ];
  final t = _Txns(acc, {for (final m in merchants) m.merchantId: m});

  // Payroll between the 5th and 7th, 12 months.
  const payDays = [5, 6, 7, 5, 6, 5, 7, 6, 5, 6, 7, 5];
  for (var i = 0; i < 12; i++) {
    final month = _d(2025, 11 + i, 1);
    t.debit(DateTime(month.year, month.month, payDays[i]), 92000 + (i * 300).toDouble(), 'SALARY BULK UPLOAD',
        payee: 'R_PAYROLL', category: 'Payroll', channel: 'NEFT');
  }
  // Sharma Yarns every Thursday for the last 10 weeks; this week's is due next.
  var nextThursday = _today;
  while (nextThursday.weekday != DateTime.thursday) {
    nextThursday = DateTime(nextThursday.year, nextThursday.month, nextThursday.day + 1);
  }
  for (var w = 10; w >= 1; w--) {
    t.debit(DateTime(nextThursday.year, nextThursday.month, nextThursday.day - 7 * w), 60000, 'RTGS SHARMA YARNS',
        payee: 'R_SHARMA', category: 'Suppliers', channel: 'RTGS');
  }
  // Electricity, GST and rent, May to October.
  const tnebDays = [4, 5, 4, 6, 5, 4];
  const tnebAmt = <double>[8100.0, 8600, 8300, 8450, 8200, 8350];
  const gstAmt = <double>[39000.0, 40000, 44000, 41000, 43000, 42000];
  for (var i = 0; i < 6; i++) {
    final month = 5 + i;
    t.debit(_d(2026, month, tnebDays[i]), tnebAmt[i], 'TNEB BILL', payee: 'R_TNEB', category: 'Utilities', channel: 'BBPS');
    t.debit(_d(2026, month, 20), gstAmt[i], 'GST CHALLAN', payee: 'R_GST', category: 'Taxes', channel: 'NEFT');
    t.debit(_d(2026, month, 1), 35000, 'SHOP RENT', payee: 'R_RENT', category: 'Rent', channel: 'NEFT');
  }
  t.debit(_d(2026, 11, 1), 35000, 'SHOP RENT', payee: 'R_RENT', category: 'Rent', channel: 'NEFT');

  // Other suppliers and running costs.
  t.debit(_d(2026, 10, 2), 30000, 'RTGS KAVERI DYES', payee: 'R_KAVERI', category: 'Suppliers', channel: 'RTGS');
  t.debit(_d(2026, 11, 3), 48000, 'RTGS KAVERI DYES', payee: 'R_KAVERI', category: 'Suppliers', channel: 'RTGS');
  for (final (m, amounts) in [
    (8, <double>[9000.0, 9000]),
    (9, <double>[9500.0, 10000]),
  ]) {
    t.spend(_d(2026, m, 3), 'M_VRL', amounts[0]);
    t.spend(_d(2026, m, 18), 'M_DTDC', amounts[1]);
  }
  t.spend(_d(2026, 10, 3), 'M_VRL', 8800);
  t.spend(_d(2026, 10, 19), 'M_DTDC', 11700);
  t.spend(_d(2026, 11, 2), 'M_VRL', 9600);
  t.spend(_d(2026, 11, 4), 'M_DTDC', 6800);
  t.spend(_d(2026, 10, 2), 'M_PACK', 5900);
  t.spend(_d(2026, 11, 3), 'M_PACK', 6400);
  t.spend(_d(2026, 10, 3), 'M_PHONE', 3000);
  t.spend(_d(2026, 11, 2), 'M_PHONE', 3100);

  // Receipts from buyers: irregular, so not a "recurring" pattern.
  for (final (d, amt) in [
    (_d(2026, 10, 9), 52000.0),
    (_d(2026, 10, 16), 41000.0),
    (_d(2026, 10, 27), 138000.0),
    (_d(2026, 11, 2), 96000.0),
  ]) {
    t.credit(d, amt, 'NEFT FROM BUYER', payee: 'R_BUYERS', category: 'Receipts');
  }

  final balances = [
    for (var i = 0; i < 60; i++)
      DailyBalance(acc, DateTime(demoToday.year, demoToday.month, demoToday.day - i),
          i == 0 ? 180000 : 40000 + ((i * 6151) % 160000).toDouble()),
  ];

  return CustomerData(
    customer: Customer(
      customerId: id,
      customerType: 'SOLE_PROPRIETOR',
      firstName: 'Rajesh',
      lastName: 'Iyer',
      dateOfBirth: _d(1981, 2, 9),
      customerSince: _d(2020, 1, 20),
      status: 'ACTIVE',
    ),
    profile: CustomerProfile(
      customerId: id,
      occupation: 'Textile trader',
      annualIncome: 2600000,
      preferredLanguage: 'Tamil',
      riskCategory: 'MODERATE',
      creditScore: 762,
      creditBureau: 'CIBIL',
      scoreDate: _d(2026, 10, 10),
    ),
    employment: const EmploymentDetails(
      customerId: id,
      employmentType: 'SELF_EMPLOYED',
      businessName: 'Iyer Textiles',
      monthlyIncome: 216000,
    ),
    persona: Persona(
      customerId: id,
      personaType: PersonaType.businessPerson,
      assignedOn: _d(2026, 10, 31),
      assignedBy: 'OCV persona model v1',
    ),
    accounts: const [
      DepositAccount(
        accountId: acc,
        customerId: id,
        accountType: AccountType.current,
        accountNumber: '60110098761122',
        currentBalance: 180000,
        availableBalance: 180000,
      ),
    ],
    fixedDeposits: const [],
    loans: const [],
    payees: payees,
    merchants: merchants,
    transactions: t.list,
    dailyBalances: balances,
    billsDue: [BillDue('R_TNEB', 8400, _d(2026, 11, 8))],
    expectedInflows: [
      ExpectedInflow(_d(2026, 11, 10), 45000, 'Lakshmi Silks'),
      ExpectedInflow(_d(2026, 11, 15), 38000, 'Ravi Garments'),
      ExpectedInflow(_d(2026, 11, 27), 140000, 'Chennai Fashion Mart'),
      ExpectedInflow(_d(2026, 12, 2), 110000, 'Kumar Exports'),
    ],
  );
}
