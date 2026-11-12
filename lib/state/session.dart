import 'package:flutter/widgets.dart';

import '../app/format.dart';
import '../data/mock_bank.dart';
import '../data/models.dart';
import '../engine/assistant.dart';
import '../engine/insights.dart';

enum Stage { loggedOut, loading, ready }

class AskTurn {
  final String question;
  final SpendView? view; // null = plain text reply
  final String? reply;

  const AskTurn(this.question, {this.view, this.reply});
}

class ActionResult {
  final bool ok;
  final String message;
  final String? detail;

  const ActionResult(this.ok, this.message, {this.detail});
}

const loadSteps = [
  'Profile and KYC',
  'Accounts and balances',
  'Transactions, last 12 months',
  'Usual payments and dues',
  'Projected cash flow',
  'Recommendations',
];

/// App state for one logged-in customer.
class BankSession extends ChangeNotifier {
  final _api = MockBankApi();

  Stage stage = Stage.loggedOut;
  AppScreen screen = AppScreen.today;
  String? loginError;
  String loadingName = '';
  int stepsDone = 0;

  CustomerData? _data;
  CustomerInsights? _insights;
  List<Obligation> todayPlan = [];
  final Set<String> paidPayees = {};
  final List<AskTurn> askTurns = [];
  final Set<String> caps = {};
  int _ref = 4200;

  CustomerData get data => _data!;
  CustomerInsights get insights => _insights!;

  List<Obligation> get unpaidToday => todayPlan.where((o) => !paidPayees.contains(o.payee.payeeId)).toList();

  /// Paid cards the customer closed with the "x". They stay paid; the card just leaves Today.
  final Set<String> dismissedPayees = {};

  /// The cards Today shows: everything in the plan except paid cards the customer closed.
  List<Obligation> get visibleToday => todayPlan.where((o) => !dismissedPayees.contains(o.payee.payeeId)).toList();

  /// Closes a paid card. Unpaid cards can't be closed, so nothing due goes missing.
  void dismissPaid(String payeeId) {
    if (!paidPayees.contains(payeeId)) return;
    dismissedPayees.add(payeeId);
    notifyListeners();
  }

  /// The signed-in customer's credentials, kept so confirmation sheets can check the MPIN.
  DemoLogin? _login;

  /// True when [mpin] is the signed-in customer's MPIN. Used to confirm payments and deposits.
  bool checkMpin(String mpin) => _login != null && _login!.mpin == mpin.trim();

  /// [loginId] is a username ("priya.sharma") or a digits-only mobile number.
  Future<void> login(String loginId, String mpin) async {
    final login = _api.authenticate(loginId, mpin);
    if (login == null) {
      loginError = 'That login and MPIN do not match a demo customer.';
      notifyListeners();
      return;
    }
    loginError = null;
    _login = login;
    loadingName = login.label.split(' ').first;
    stepsDone = 0;
    stage = Stage.loading;
    notifyListeners();

    final data = await _api.loadCustomer(login.customerId);
    for (var i = 0; i < loadSteps.length; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 380));
      stepsDone = i + 1;
      notifyListeners();
    }
    _setData(data);
    todayPlan = insights.todayItems();
    paidPayees.clear();
    dismissedPayees.clear();
    askTurns.clear();
    caps.clear();
    screen = AppScreen.today;
    stage = Stage.ready;
    notifyListeners();
  }

  void logout() {
    stage = Stage.loggedOut;
    _login = null;
    _data = null;
    _insights = null;
    notifyListeners();
  }

  void go(AppScreen s) {
    if (s == AppScreen.ask && askTurns.isEmpty) {
      askTurns.add(const AskTurn('Where did my money go this month?', view: SpendView.summary));
    }
    screen = s;
    notifyListeners();
  }

  void ask(String question, SpendView view) {
    askTurns.add(AskTurn(question, view: view));
    screen = AppScreen.ask;
    notifyListeners();
  }

  void reply(String question, String text) {
    askTurns.add(AskTurn(question, reply: text));
    screen = AppScreen.ask;
    notifyListeners();
  }

  /// After a completed transaction: back to Today with a fresh conversation.
  void finishAction() {
    askTurns.clear();
    screen = AppScreen.today;
    notifyListeners();
  }

  void setCap(String category) {
    caps.add(category);
    notifyListeners();
  }

  void _setData(CustomerData d) {
    _data = d;
    _insights = CustomerInsights(d);
  }

  String _nextRef(String prefix) => '$prefix${_ref++}';

  DepositAccount get _account => data.primaryAccount;

  void _replaceAccount(DepositAccount updated, {List<Transaction> add = const [], List<BillDue>? bills,
      List<FixedDeposit>? fds, List<LoanAccount>? loans}) {
    _setData(data.copyWith(
      accounts: [updated, ...data.accounts.skip(1)],
      transactions: [...data.transactions, ...add],
      billsDue: bills,
      fixedDeposits: fds,
      loans: loans,
    ));
  }

  Transaction _txn(TransactionType type, double amount, String description, String category, {String? payee}) =>
      Transaction(
        transactionId: _nextRef('${_account.accountId}-AI'),
        accountId: _account.accountId,
        transactionType: type,
        amount: amount,
        transactionTimestamp: DateTime(demoToday.year, demoToday.month, demoToday.day, 9, 5),
        description: description,
        channel: 'AI_MODE',
        category: category,
        payeeId: payee,
      );

  ActionResult pay(List<Obligation> items) {
    final total = items.fold<double>(0, (s, o) => s + o.amount);
    if (total > _account.availableBalance) {
      return ActionResult(false, 'Not enough balance',
          detail: 'You need ${inr(total)} and have ${inr(_account.availableBalance)} available.');
    }
    final txns = <Transaction>[];
    for (final o in items) {
      final category = data.transactions
              .where((t) => t.payeeId == o.payee.payeeId)
              .map((t) => t.category)
              .lastOrNull ??
          'Bills';
      txns.add(_txn(TransactionType.debit, o.amount, 'AI MODE PAY ${o.payee.name.toUpperCase()}', category,
          payee: o.payee.payeeId));
      paidPayees.add(o.payee.payeeId);
    }
    final paidIds = items.map((o) => o.payee.payeeId).toSet();
    _replaceAccount(
      _account.copyWith(
        currentBalance: _account.currentBalance - total,
        availableBalance: _account.availableBalance - total,
      ),
      add: txns,
      bills: data.billsDue.where((b) => !paidIds.contains(b.payeeId)).toList(),
    );
    notifyListeners();
    final who = items.length == 1 ? items.first.payee.name : '${items.length} payments';
    return ActionResult(true, 'Paid ${inr(total)} · $who', detail: 'Ref ${_nextRef('UTR')}');
  }

  ActionResult bookDeposit(ProductOffer p, double amount, int months) {
    if (amount > _account.currentBalance) {
      return ActionResult(false, 'Not enough balance', detail: 'Available: ${inr(_account.currentBalance)}');
    }
    final isRd = p.code == 'RD';
    final maturity = isRd ? rdMaturity(amount, p.rate, months) : fdMaturity(amount, p.rate, months);
    final start = dateOnly(demoToday);
    final fd = FixedDeposit(
      fdId: _nextRef('FD-'),
      customerId: data.customer.customerId,
      linkedAccountId: _account.accountId,
      fdNumber: _nextRef('7700012'),
      productCode: p.code,
      principalAmount: isRd ? amount * months : amount,
      interestRate: p.rate,
      tenureMonths: months,
      startDate: start,
      maturityDate: DateTime(start.year, start.month + months, start.day),
      maturityAmount: maturity,
      autoRenewal: p.code == 'SWEEP_FD',
      status: 'ACTIVE',
    );
    // An RD debits the first instalment today; an FD moves the whole amount.
    final debit = amount;
    _replaceAccount(
      _account.copyWith(
        currentBalance: _account.currentBalance - debit,
        availableBalance: _account.availableBalance - debit,
      ),
      add: [_txn(TransactionType.debit, debit, 'AI MODE ${p.name.toUpperCase()}', 'Investments')],
      fds: [...data.fixedDeposits, fd],
    );
    notifyListeners();
    return ActionResult(
      true,
      isRd ? 'Recurring Deposit opened' : '${p.name} booked',
      detail: '${isRd ? 'RD' : 'FD'} no. ${fd.fdNumber} · matures ${longDate(fd.maturityDate)} at ${inr(maturity)}',
    );
  }

  ActionResult acceptCredit(ProductOffer p, double amount, int months) {
    final isOd = p.code == 'BIZ_OD';
    final loan = LoanAccount(
      loanId: _nextRef('LN-'),
      customerId: data.customer.customerId,
      loanAccountNumber: _nextRef('8800034'),
      productCode: p.code,
      loanType: p.name,
      sanctionedAmount: amount,
      outstandingAmount: isOd ? 0 : amount,
      interestRate: p.rate,
      emiAmount: isOd ? 0 : emi(amount, p.rate, months),
      sanctionDate: dateOnly(demoToday),
      status: 'ACTIVE',
    );
    if (isOd) {
      // A limit, not a disbursal: available balance goes up, own funds do not.
      _replaceAccount(_account.copyWith(availableBalance: _account.availableBalance + amount),
          loans: [...data.loans, loan]);
    } else {
      _replaceAccount(
        _account.copyWith(
          currentBalance: _account.currentBalance + amount,
          availableBalance: _account.availableBalance + amount,
        ),
        add: [_txn(TransactionType.credit, amount, 'LOAN DISBURSAL ${p.name.toUpperCase()}', 'Loan')],
        loans: [...data.loans, loan],
      );
    }
    notifyListeners();
    return ActionResult(
      true,
      isOd ? 'Overdraft limit of ${inr(amount)} is live' : '${p.name} of ${inr(amount)} disbursed',
      detail: isOd
          ? 'Account ${loan.loanAccountNumber} · interest only on what you use'
          : 'Account ${loan.loanAccountNumber} · EMI ${inr(loan.emiAmount)} for $months months',
    );
  }
}

class SessionScope extends InheritedNotifier<BankSession> {
  const SessionScope({super.key, required BankSession session, required super.child}) : super(notifier: session);

  static BankSession of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>()!.notifier!;
}
