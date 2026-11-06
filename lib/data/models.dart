// Domain models for the mock. Names follow the team's data model
// (Customer, CustomerProfile, DepositAccount, ...) in Dart style.
// Classes marked NEW are additions the FD / recommendation scenario needs.

enum PersonaType { salaryCustomer, businessPerson, seniorCitizen }

enum AccountType { savings, current }

enum TransactionType { debit, credit }

enum PayeeKind { person, biller, vendor, employer, statutory, landlord, payroll, card }

class Customer {
  final String customerId;
  final String customerType; // INDIVIDUAL, SOLE_PROPRIETOR
  final String firstName;
  final String lastName;
  final DateTime dateOfBirth;
  final DateTime customerSince;
  final String status;

  const Customer({
    required this.customerId,
    required this.customerType,
    required this.firstName,
    required this.lastName,
    required this.dateOfBirth,
    required this.customerSince,
    required this.status,
  });

  String get initials => '${firstName[0]}${lastName[0]}';
}

class CustomerProfile {
  final String customerId;
  final String occupation;
  final double annualIncome;
  final String preferredLanguage;
  final String riskCategory;
  final int creditScore;
  final String creditBureau;
  final DateTime scoreDate;

  const CustomerProfile({
    required this.customerId,
    required this.occupation,
    required this.annualIncome,
    required this.preferredLanguage,
    required this.riskCategory,
    required this.creditScore,
    required this.creditBureau,
    required this.scoreDate,
  });
}

class EmploymentDetails {
  final String customerId;
  final String employmentType; // SALARIED, SELF_EMPLOYED
  final String? employerName;
  final String? businessName;
  final double monthlyIncome;

  const EmploymentDetails({
    required this.customerId,
    required this.employmentType,
    this.employerName,
    this.businessName,
    required this.monthlyIncome,
  });
}

class Persona {
  final String customerId;
  final PersonaType personaType;
  final DateTime assignedOn;
  final String assignedBy;

  const Persona({
    required this.customerId,
    required this.personaType,
    required this.assignedOn,
    required this.assignedBy,
  });

  String get label => switch (personaType) {
        PersonaType.salaryCustomer => 'Salary customer',
        PersonaType.businessPerson => 'Business account holder',
        PersonaType.seniorCitizen => 'Senior citizen',
      };
}

class DepositAccount {
  final String accountId;
  final String customerId;
  final AccountType accountType;
  final String accountNumber;
  final double currentBalance;
  final double availableBalance;
  final String currency;

  const DepositAccount({
    required this.accountId,
    required this.customerId,
    required this.accountType,
    required this.accountNumber,
    required this.currentBalance,
    required this.availableBalance,
    this.currency = 'INR',
  });

  DepositAccount copyWith({double? currentBalance, double? availableBalance}) =>
      DepositAccount(
        accountId: accountId,
        customerId: customerId,
        accountType: accountType,
        accountNumber: accountNumber,
        currentBalance: currentBalance ?? this.currentBalance,
        availableBalance: availableBalance ?? this.availableBalance,
        currency: currency,
      );

  String get maskedNumber => 'xx${accountNumber.substring(accountNumber.length - 4)}';
}

class FixedDeposit {
  final String fdId;
  final String customerId;
  final String linkedAccountId;
  final String fdNumber;
  final String productCode;
  final double principalAmount;
  final double interestRate;
  final int tenureMonths;
  final DateTime startDate;
  final DateTime maturityDate;
  final double maturityAmount;
  final bool autoRenewal;
  final String status;

  const FixedDeposit({
    required this.fdId,
    required this.customerId,
    required this.linkedAccountId,
    required this.fdNumber,
    required this.productCode,
    required this.principalAmount,
    required this.interestRate,
    required this.tenureMonths,
    required this.startDate,
    required this.maturityDate,
    required this.maturityAmount,
    required this.autoRenewal,
    required this.status,
  });
}

class LoanAccount {
  final String loanId;
  final String customerId;
  final String loanAccountNumber;
  final String productCode;
  final String loanType;
  final double sanctionedAmount;
  final double outstandingAmount;
  final double interestRate;
  final double emiAmount;
  final DateTime sanctionDate;
  final String status;

  const LoanAccount({
    required this.loanId,
    required this.customerId,
    required this.loanAccountNumber,
    required this.productCode,
    required this.loanType,
    required this.sanctionedAmount,
    required this.outstandingAmount,
    required this.interestRate,
    required this.emiAmount,
    required this.sanctionDate,
    required this.status,
  });
}

class Merchant {
  final String merchantId;
  final String merchantName;
  final String category;

  const Merchant(this.merchantId, this.merchantName, this.category);
}

/// NEW: who money goes to or comes from. Needed to detect "you usually pay X".
class Payee {
  final String payeeId;
  final String name;
  final PayeeKind kind;

  const Payee(this.payeeId, this.name, this.kind);
}

class Transaction {
  final String transactionId;
  final String accountId;
  final TransactionType transactionType;
  final double amount;
  final DateTime transactionTimestamp;
  final String description;
  final String channel;
  final String category;
  final String? merchantId;
  final String? payeeId;

  const Transaction({
    required this.transactionId,
    required this.accountId,
    required this.transactionType,
    required this.amount,
    required this.transactionTimestamp,
    required this.description,
    required this.channel,
    required this.category,
    this.merchantId,
    this.payeeId,
  });

  bool get isDebit => transactionType == TransactionType.debit;
}

/// NEW: end-of-day balance from CBS. Drives "idle for N days".
class DailyBalance {
  final String accountId;
  final DateTime date;
  final double eodBalance;

  const DailyBalance(this.accountId, this.date, this.eodBalance);
}

/// NEW: a presented bill (BBPS, card statement). Gives the exact amount and due date.
class BillDue {
  final String payeeId;
  final double amount;
  final DateTime dueDate;
  final bool usuallyPaidInFull;

  const BillDue(this.payeeId, this.amount, this.dueDate, {this.usuallyPaidInFull = false});
}

/// NEW: money the bank expects in (receivables, invoices raised). Business cash flow.
class ExpectedInflow {
  final DateTime date;
  final double amount;
  final String source;

  const ExpectedInflow(this.date, this.amount, this.source);
}

enum ProductKind { deposit, credit }

/// NEW: product catalogue entry. Rates are illustrative for the mock.
class ProductOffer {
  final String code;
  final String name;
  final String tagline;
  final double rate;
  final ProductKind kind;
  final int defaultTenureMonths;

  const ProductOffer({
    required this.code,
    required this.name,
    required this.tagline,
    required this.rate,
    required this.kind,
    required this.defaultTenureMonths,
  });
}

/// Everything the bank knows about one customer, as loaded after login.
class CustomerData {
  final Customer customer;
  final CustomerProfile profile;
  final EmploymentDetails employment;
  final Persona persona;
  final List<DepositAccount> accounts;
  final List<FixedDeposit> fixedDeposits;
  final List<LoanAccount> loans;
  final List<Payee> payees;
  final List<Merchant> merchants;
  final List<Transaction> transactions;
  final List<DailyBalance> dailyBalances;
  final List<BillDue> billsDue;
  final List<ExpectedInflow> expectedInflows;

  const CustomerData({
    required this.customer,
    required this.profile,
    required this.employment,
    required this.persona,
    required this.accounts,
    required this.fixedDeposits,
    required this.loans,
    required this.payees,
    required this.merchants,
    required this.transactions,
    required this.dailyBalances,
    required this.billsDue,
    required this.expectedInflows,
  });

  DepositAccount get primaryAccount => accounts.first;

  Payee payee(String id) => payees.firstWhere((p) => p.payeeId == id);

  CustomerData copyWith({
    List<DepositAccount>? accounts,
    List<FixedDeposit>? fixedDeposits,
    List<LoanAccount>? loans,
    List<Transaction>? transactions,
    List<BillDue>? billsDue,
  }) =>
      CustomerData(
        customer: customer,
        profile: profile,
        employment: employment,
        persona: persona,
        accounts: accounts ?? this.accounts,
        fixedDeposits: fixedDeposits ?? this.fixedDeposits,
        loans: loans ?? this.loans,
        payees: payees,
        merchants: merchants,
        transactions: transactions ?? this.transactions,
        dailyBalances: dailyBalances,
        billsDue: billsDue ?? this.billsDue,
        expectedInflows: expectedInflows,
      );
}
