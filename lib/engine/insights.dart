import 'dart:math' as math;

import '../app/format.dart';
import '../data/mock_bank.dart';
import '../data/models.dart';

// Non-AI engine: every figure the screens show is computed here from the
// customer's data. In the full solution the LLM only words these results.

enum Cadence { monthly, weekly }

class RecurringPattern {
  final Payee payee;
  final TransactionType type;
  final Cadence cadence;
  final List<Transaction> history; // oldest first
  final int minDay;
  final int maxDay;

  RecurringPattern(this.payee, this.type, this.cadence, this.history)
      : minDay = history.map((t) => t.transactionTimestamp.day).reduce(math.min),
        maxDay = history.map((t) => t.transactionTimestamp.day).reduce(math.max);

  Transaction get last => history.last;
  double get lastAmount => last.amount;
  int get streak => history.length;
  int get weekday => last.transactionTimestamp.weekday;

  double get recentAverage {
    final recent = history.reversed.take(3).toList();
    return recent.fold<double>(0, (s, t) => s + t.amount) / recent.length;
  }
}

/// Finds payees paid (or paying in) on a steady monthly or weekly rhythm.
List<RecurringPattern> detectRecurring(CustomerData data) {
  final groups = <String, List<Transaction>>{};
  for (final t in data.transactions) {
    final id = t.payeeId;
    if (id == null) continue;
    if (data.payee(id).kind == PayeeKind.card) continue; // card bills come from the statement
    groups.putIfAbsent('$id|${t.transactionType.name}', () => []).add(t);
  }
  final patterns = <RecurringPattern>[];
  for (final txns in groups.values) {
    if (txns.length < 3) continue;
    txns.sort((a, b) => a.transactionTimestamp.compareTo(b.transactionTimestamp));
    final gaps = [
      for (var i = 1; i < txns.length; i++)
        dateOnly(txns[i].transactionTimestamp).difference(dateOnly(txns[i - 1].transactionTimestamp)).inDays,
    ];
    Cadence? cadence;
    if (gaps.every((g) => g >= 6 && g <= 8)) {
      cadence = Cadence.weekly;
    } else if (gaps.every((g) => g >= 25 && g <= 37)) {
      cadence = Cadence.monthly;
    }
    if (cadence == null) continue;
    patterns.add(RecurringPattern(data.payee(txns.first.payeeId!), txns.first.transactionType, cadence, txns));
  }
  return patterns;
}

/// Something the customer is expected to pay soon.
class Obligation {
  final Payee payee;
  final double amount;
  final DateTime expectedDate;
  final String reason;
  final String actionLabel;

  const Obligation(this.payee, this.amount, this.expectedDate, this.reason, this.actionLabel);
}

class CashEvent {
  final DateTime date;
  final double amount; // + in, - out
  final String label;

  const CashEvent(this.date, this.amount, this.label);
}

class CategorySpend {
  final String name;
  final double amount;
  final double lastMonthSamePoint;

  const CategorySpend(this.name, this.amount, this.lastMonthSamePoint);
}

class SpendInsight {
  final String category;
  final String message;
  final double cap;
  final String primaryLabel;
  final String secondaryLabel;
  final bool mostlyWeekends;

  const SpendInsight({
    required this.category,
    required this.message,
    required this.cap,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.mostlyWeekends,
  });
}

class SpendSummary {
  final DateTime today;
  final double total;
  final double lastMonthSamePoint;
  final List<CategorySpend> categories;
  final SpendInsight? insight;

  const SpendSummary(this.today, this.total, this.lastMonthSamePoint, this.categories, this.insight);

  double get changePct => lastMonthSamePoint == 0 ? 0 : (total / lastMonthSamePoint - 1) * 100;
}

enum RecommendationKind { invest, credit, covered, working }

/// The "what should this customer do next" answer for the grow screen.
class Recommendation {
  final RecommendationKind kind;
  final String eyebrow;
  final String headline;
  final String subline;
  final List<OfferLine> offers;
  final double amount; // sweep amount or overdraft limit
  final String primaryCta;
  final String secondaryCta;
  final String remindOn;
  final List<String> workings; // "How we worked this out"

  // Invest
  final int idleDays;
  // Credit
  final List<double> projection; // daily own-funds balance, today first
  final double shortfall;
  final DateTime? shortfallDate;
  final int daysShort;

  const Recommendation({
    required this.kind,
    required this.eyebrow,
    required this.headline,
    required this.subline,
    this.offers = const [],
    this.amount = 0,
    this.primaryCta = '',
    this.secondaryCta = '',
    this.remindOn = '',
    this.workings = const [],
    this.idleDays = 0,
    this.projection = const [],
    this.shortfall = 0,
    this.shortfallDate,
    this.daysShort = 0,
  });
}

class OfferLine {
  final ProductOffer product;
  final String note;
  final double amount;

  const OfferLine(this.product, this.note, this.amount);
}

const _minBuffer = 5000.0;
const _creditBuffer = 25000.0;
const _horizonDays = 30;
const _nonSpend = {'Salary', 'Income', 'Receipts', 'Transfers', 'Card payment', 'Investments', 'Loan'};
const _fixed = {'Bills', 'Rent', 'Payroll', 'Taxes', 'Utilities'};
const _discretionary = {'Food', 'Shopping', 'Travel', 'Entertainment', 'Personal care'};

double _floorTo(double v, double step) => (v / step).floorToDouble() * step;
double _ceilTo(double v, double step) => (v / step).ceilToDouble() * step;

class CustomerInsights {
  final CustomerData data;
  final DateTime today;
  late final List<RecurringPattern> patterns = detectRecurring(data);

  CustomerInsights(this.data, {DateTime? today}) : today = dateOnly(today ?? demoToday);

  bool get isBusiness => data.persona.personaType == PersonaType.businessPerson;

  // Calendar arithmetic, safe across DST in the viewer's timezone.
  DateTime _plusDays(int days) => DateTime(today.year, today.month, today.day + days);
  DepositAccount get account => data.primaryAccount;
  double get ownBalance => account.currentBalance;

  double get overdraftLimit => data.loans
      .where((l) => l.productCode == 'BIZ_OD' && l.status == 'ACTIVE')
      .fold<double>(0, (s, l) => s + l.sanctionedAmount - l.outstandingAmount);

  // ------------------------------------------------------------- obligations

  bool _paidThisCycle(RecurringPattern p) {
    final last = dateOnly(p.last.transactionTimestamp);
    return switch (p.cadence) {
      Cadence.monthly => last.year == today.year && last.month == today.month,
      Cadence.weekly => today.difference(last).inDays < 7,
    };
  }

  DateTime _thisCycleDate(RecurringPattern p) => switch (p.cadence) {
        Cadence.monthly => today.day >= p.minDay && today.day <= p.maxDay
            ? today
            : DateTime(today.year, today.month, p.maxDay),
        Cadence.weekly => dateOnly(p.last.transactionTimestamp).add(const Duration(days: 7)),
      };

  String _reason(RecurringPattern p) {
    if (p.cadence == Cadence.weekly) return 'Every ${weekdayName(p.last.transactionTimestamp)} for ${p.streak} weeks';
    if (p.minDay == p.maxDay) return 'Paid on the ${ordinal(p.minDay)} for ${p.streak} months running';
    return 'Monthly, usually between the ${ordinal(p.minDay)} and ${ordinal(p.maxDay)}';
  }

  String _action(Payee payee, BillDue? bill) => switch (payee.kind) {
        PayeeKind.person => 'Send',
        PayeeKind.card => bill?.usuallyPaidInFull == true ? 'Pay in full' : 'Pay',
        PayeeKind.payroll => 'Pay salaries',
        PayeeKind.biller => 'Pay now',
        _ => 'Pay',
      };

  BillDue? _bill(String payeeId) {
    for (final b in data.billsDue) {
      if (b.payeeId == payeeId) return b;
    }
    return null;
  }

  /// Every unpaid obligation in the current cycle, soonest first.
  List<Obligation> currentObligations() {
    final items = <(Obligation, int)>[];
    var order = 0;
    final covered = <String>{};
    for (final p in patterns) {
      if (p.type != TransactionType.debit || _paidThisCycle(p)) continue;
      final bill = _bill(p.payee.payeeId);
      covered.add(p.payee.payeeId);
      items.add((
        Obligation(p.payee, bill?.amount ?? p.lastAmount, _thisCycleDate(p), _reason(p), _action(p.payee, bill)),
        order++,
      ));
    }
    for (final b in data.billsDue) {
      if (covered.contains(b.payeeId)) continue;
      final payee = data.payee(b.payeeId);
      final reason = b.usuallyPaidInFull
          ? 'Due ${shortDate(b.dueDate)}. You usually pay in full'
          : 'Due ${shortDate(b.dueDate)}';
      items.add((Obligation(payee, b.amount, dateOnly(b.dueDate), reason, _action(payee, b)), order++));
    }
    items.sort((a, b) {
      final c = a.$1.expectedDate.compareTo(b.$1.expectedDate);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
    return [for (final i in items) i.$1];
  }

  /// "Here's what you usually do around now": due within the next 4 days.
  List<Obligation> todayItems() {
    final until = _plusDays(4);
    return currentObligations().where((o) => !o.expectedDate.isAfter(until)).toList();
  }

  // --------------------------------------------------------------- cash flow

  List<CashEvent> cashEvents({int days = _horizonDays}) {
    final end = _plusDays(days);
    final events = <CashEvent>[
      for (final o in currentObligations())
        if (!o.expectedDate.isAfter(end)) CashEvent(o.expectedDate, -o.amount, o.payee.name),
    ];
    for (final p in patterns) {
      final sign = p.type == TransactionType.credit ? 1.0 : -1.0;
      // The current cycle's payment is already in currentObligations().
      var next = switch (p.cadence) {
        Cadence.monthly => DateTime(today.year, today.month + 1, p.maxDay),
        Cadence.weekly => _paidThisCycle(p) ? _thisCycleDate(p) : _thisCycleDate(p).add(const Duration(days: 7)),
      };
      // Inflows not yet received this month still count.
      if (p.type == TransactionType.credit && !_paidThisCycle(p) && p.cadence == Cadence.monthly) {
        next = DateTime(today.year, today.month, p.maxDay);
      }
      while (!next.isAfter(end)) {
        if (!next.isBefore(today)) events.add(CashEvent(next, sign * p.recentAverage, p.payee.name));
        next = switch (p.cadence) {
          Cadence.monthly => DateTime(next.year, next.month + 1, p.maxDay),
          Cadence.weekly => next.add(const Duration(days: 7)),
        };
      }
    }
    for (final e in data.expectedInflows) {
      if (!e.date.isBefore(today) && !e.date.isAfter(end)) events.add(CashEvent(e.date, e.amount, e.source));
    }
    events.sort((a, b) => a.date.compareTo(b.date));
    return events;
  }

  /// End-of-day own-funds balance for today and each of the next [days] days.
  List<double> projection({int days = _horizonDays}) {
    final events = cashEvents(days: days);
    var balance = ownBalance;
    return [
      for (var i = 0; i <= days; i++)
        () {
          final day = _plusDays(i);
          for (final e in events.where((e) => e.date == day)) {
            balance += e.amount;
          }
          return balance;
        }(),
    ];
  }

  RecurringPattern? get salaryPattern {
    for (final p in patterns) {
      if (p.type == TransactionType.credit && p.payee.kind == PayeeKind.employer) return p;
    }
    return null;
  }

  DateTime? get nextSalaryDate {
    for (final e in cashEvents(days: 40)) {
      if (e.amount > 0 && salaryPattern != null && e.label == salaryPattern!.payee.name) return e.date;
    }
    return null;
  }

  int idleDays() {
    final threshold = 1.5 * data.employment.monthlyIncome;
    if (ownBalance < threshold) return 0;
    final history = [...data.dailyBalances]..sort((a, b) => b.date.compareTo(a.date));
    var days = 1; // today, at the current balance
    for (final b in history) {
      if (!b.date.isBefore(today)) continue;
      if (b.eodBalance < threshold) break;
      days++;
    }
    return days;
  }

  // ---------------------------------------------------------- recommendation

  Recommendation recommend() {
    final proj = projection();
    final minIndex = List.generate(proj.length, (i) => i).reduce((a, b) => proj[a] <= proj[b] ? a : b);
    final minBalance = proj[minIndex];

    if (minBalance < 0) {
      final shortfall = -minBalance;
      final minDate = _plusDays(minIndex);
      final daysShort = proj.where((b) => b < 0).length;
      if (overdraftLimit + minBalance >= 0) {
        return Recommendation(
          kind: RecommendationKind.covered,
          eyebrow: 'Cash flow covered',
          headline: 'Your overdraft covers the dip around ${shortDate(minDate)}.',
          subline:
              'You may draw up to ${inr(shortfall)} for about $daysShort days. Interest applies only to what you use.',
          projection: proj,
          shortfall: shortfall,
          shortfallDate: minDate,
          daysShort: daysShort,
          amount: overdraftLimit,
        );
      }
      final limit = _ceilTo(shortfall + _creditBuffer, 50000);
      final gst = patterns.where((p) => p.payee.kind == PayeeKind.statutory).firstOrNull;
      final remindDate = gst != null
          ? _nextMonthlyDate(gst.maxDay).subtract(const Duration(days: 2))
          : _plusDays(7);
      final od = product('BIZ_OD');
      return Recommendation(
        kind: RecommendationKind.credit,
        eyebrow: 'Stay ahead of cash flow',
        headline: 'Your account may run ${inr(shortfall)} short around ${shortDate(minDate)}.',
        subline: 'Here are your next 30 days, from your usual payments and expected receipts.',
        offers: [
          OfferLine(od, od.tagline, limit),
          OfferLine(product('WC_LOAN'), product('WC_LOAN').tagline, limit),
          OfferLine(product('BIZ_LOAN'), product('BIZ_LOAN').tagline, limit * 2),
        ],
        amount: limit,
        primaryCta: 'Get ${inr(limit)} overdraft limit',
        secondaryCta: gst != null ? 'Not now, remind me before GST day' : 'Not now, remind me next week',
        remindOn: shortDate(remindDate),
        projection: proj,
        shortfall: shortfall,
        shortfallDate: minDate,
        daysShort: daysShort,
        workings: [
          'Balance today: ${inr(ownBalance)}',
          'Lowest point in 30 days: ${inr(minBalance)} on ${shortDate(minDate)}',
          'Safety buffer: ${inr(_creditBuffer)}',
          'Limit, rounded up to ₹50,000: ${inr(limit)}',
          'Credit score ${data.profile.creditScore} (${data.profile.creditBureau}): eligible',
        ],
      );
    }

    // Never suggest investing borrowed money.
    final activeLoan = data.loans.where((l) => l.status == 'ACTIVE').firstOrNull;
    if (activeLoan != null) {
      return Recommendation(
        kind: RecommendationKind.covered,
        eyebrow: 'Cash flow covered',
        headline: 'Your next 30 days are covered.',
        subline: 'Your ${activeLoan.loanType.toLowerCase()} keeps the balance above zero through '
            '${shortDate(_plusDays(_horizonDays))}.',
        projection: proj,
      );
    }

    final salaryDay = nextSalaryDate ??_plusDays(_horizonDays);
    final dueBeforeSalary = cashEvents()
        .where((e) => e.amount < 0 && e.date.isBefore(salaryDay))
        .fold<double>(0, (s, e) => s - e.amount);
    final sweep = _floorTo(ownBalance - dueBeforeSalary - _minBuffer, 10000);
    if (sweep >= 25000) {
      final spendReserve = 0.5 * data.employment.monthlyIncome;
      final lockAmount = math.max(0.0, _floorTo(ownBalance - dueBeforeSalary - spendReserve - _minBuffer, 10000));
      final rdMonthly = math.max(1000.0, _floorTo(0.12 * data.employment.monthlyIncome, 5000));
      final sweepFd = product('SWEEP_FD');
      return Recommendation(
        kind: RecommendationKind.invest,
        eyebrow: 'Make it work harder',
        headline: '${inr(ownBalance)} has sat idle in savings for ${idleDays()} days.',
        subline: 'Here is what the same money could look like with us.',
        offers: [
          OfferLine(sweepFd, sweepFd.tagline, sweep),
          OfferLine(product('FD_1Y'), product('FD_1Y').tagline, lockAmount),
          OfferLine(product('RD'), '${inr(rdMonthly)} a month, built from salary', rdMonthly),
        ],
        amount: sweep,
        primaryCta: 'Move ${inr(sweep)} to Auto-sweep FD',
        secondaryCta: 'Not now, remind me on salary day',
        remindOn: shortDate(salaryDay),
        idleDays: idleDays(),
        workings: [
          'Balance today: ${inr(ownBalance)}',
          'Due before salary on ${shortDate(salaryDay)}: ${inr(dueBeforeSalary)}',
          'Minimum buffer kept: ${inr(_minBuffer)}',
          'Rounded down to ₹10,000: ${inr(sweep)}',
          'Sweep FD breaks automatically if your balance runs short',
        ],
      );
    }

    final invested = data.fixedDeposits.fold<double>(0, (s, f) => s + f.principalAmount);
    return Recommendation(
      kind: RecommendationKind.working,
      eyebrow: 'Your money is working',
      headline: invested > 0
          ? '${inr(invested)} is now earning in deposits.'
          : 'Nothing idle right now.',
      subline: 'We will look again when your next salary or receipt lands.',
    );
  }

  DateTime _nextMonthlyDate(int day) {
    final thisMonth = DateTime(today.year, today.month, day);
    return thisMonth.isBefore(today) ? DateTime(today.year, today.month + 1, day) : thisMonth;
  }

  // ------------------------------------------------------------------ spends

  bool _isSpend(Transaction t) => t.isDebit && !_nonSpend.contains(t.category);

  Iterable<Transaction> _spendsBetween(DateTime from, DateTime toInclusive) => data.transactions.where((t) {
        final d = dateOnly(t.transactionTimestamp);
        return _isSpend(t) && !d.isBefore(from) && !d.isAfter(toInclusive);
      });

  Iterable<Transaction> monthToDate([String? category]) =>
      _spendsBetween(DateTime(today.year, today.month, 1), today)
          .where((t) => category == null || t.category == category);

  SpendSummary spendSummary() {
    final lastStart = DateTime(today.year, today.month - 1, 1);
    final lastSamePoint = DateTime(today.year, today.month - 1, today.day);
    final now = <String, double>{};
    final before = <String, double>{};
    for (final t in monthToDate()) {
      now[t.category] = (now[t.category] ?? 0) + t.amount;
    }
    for (final t in _spendsBetween(lastStart, lastSamePoint)) {
      before[t.category] = (before[t.category] ?? 0) + t.amount;
    }
    final categories = [
      for (final c in now.keys) CategorySpend(c, now[c]!, before[c] ?? 0),
    ]..sort((a, b) => b.amount.compareTo(a.amount));
    final total = now.values.fold<double>(0, (s, v) => s + v);
    final totalBefore = before.values.fold<double>(0, (s, v) => s + v);
    return SpendSummary(today, total, totalBefore, categories, _spendInsight(categories));
  }

  SpendInsight? _spendInsight(List<CategorySpend> categories) {
    CategorySpend? best;
    for (final c in categories) {
      if (_fixed.contains(c.name) || c.amount < 2000 || c.amount - c.lastMonthSamePoint < 2000) continue;
      final ratio = c.lastMonthSamePoint == 0 ? double.infinity : c.amount / c.lastMonthSamePoint;
      final bestRatio = best == null
          ? -1.0
          : (best.lastMonthSamePoint == 0 ? double.infinity : best.amount / best.lastMonthSamePoint);
      if (ratio > bestRatio) best = c;
    }
    if (best == null) return null;
    final c = best;
    final cap = (_averageFullMonths(c.name, 3) / 1000).roundToDouble() * 1000;
    // TODO(parked): "mostly on weekends" can contradict the calendar. On 7 Nov 2026 (the
    // first Saturday) it rests on a single weekend day, Sunday 1 Nov, which a keen eye
    // will question. Only claim it once at least one full weekend has passed this month,
    // and say which weekend days it means. See the weekend TODO in mock_bank.dart.
    final weekendShare = weekendSplit(c.name).$1 / c.amount;
    final mostlyWeekends = weekendShare > 0.5;
    final upPct = c.lastMonthSamePoint == 0 ? 100 : ((c.amount / c.lastMonthSamePoint - 1) * 100).round();
    if (isBusiness || !_discretionary.contains(c.name)) {
      return SpendInsight(
        category: c.name,
        message: '${c.name} costs are up $upPct% on last month. Want an alert if they cross ${inr(cap)}?',
        cap: cap,
        primaryLabel: 'Set ${inr(cap)} alert',
        secondaryLabel: 'Show by vendor',
        mostlyWeekends: mostlyWeekends,
      );
    }
    final label = c.name == 'Food' ? 'Dining out' : c.name;
    return SpendInsight(
      category: c.name,
      message: mostlyWeekends
          ? "$label is up, mostly on weekends. Want a cap so it doesn't creep?"
          : "$label is up $upPct% on last month. Want a cap so it doesn't creep?",
      cap: cap,
      primaryLabel: 'Set ${inr(cap)} cap',
      secondaryLabel: mostlyWeekends ? 'Show weekends' : 'Show merchants',
      mostlyWeekends: mostlyWeekends,
    );
  }

  double _averageFullMonths(String category, int months) {
    var total = 0.0;
    for (var i = 1; i <= months; i++) {
      final start = DateTime(today.year, today.month - i, 1);
      final end = DateTime(today.year, today.month - i + 1, 0);
      total += _spendsBetween(start, end).where((t) => t.category == category).fold<double>(0, (s, t) => s + t.amount);
    }
    return total / months;
  }

  /// (weekend, weekday) month-to-date spend for a category.
  (double, double) weekendSplit(String category) {
    var weekend = 0.0, weekday = 0.0;
    for (final t in monthToDate(category)) {
      final wd = t.transactionTimestamp.weekday;
      if (wd == DateTime.saturday || wd == DateTime.sunday) {
        weekend += t.amount;
      } else {
        weekday += t.amount;
      }
    }
    return (weekend, weekday);
  }

  /// Month-to-date spend in a category, by merchant or payee, largest first.
  List<(String, double)> byCounterparty(String category) {
    final totals = <String, double>{};
    for (final t in monthToDate(category)) {
      final name = t.merchantId != null
          ? data.merchants.firstWhere((m) => m.merchantId == t.merchantId).merchantName
          : (t.payeeId != null ? data.payee(t.payeeId!).name : t.description);
      totals[name] = (totals[name] ?? 0) + t.amount;
    }
    final list = [for (final e in totals.entries) (e.key, e.value)];
    list.sort((a, b) => b.$2.compareTo(a.$2));
    return list;
  }
}

// ------------------------------------------------------------- calculators

/// FD maturity with quarterly compounding.
double fdMaturity(double principal, double ratePct, int months) =>
    principal * math.pow(1 + ratePct / 400, months / 3).toDouble();

/// RD maturity: each monthly instalment compounds quarterly until maturity.
double rdMaturity(double monthly, double ratePct, int months) {
  var total = 0.0;
  for (var k = 0; k < months; k++) {
    total += monthly * math.pow(1 + ratePct / 400, (months - k) / 3).toDouble();
  }
  return total;
}

double emi(double principal, double ratePct, int months) {
  final r = ratePct / 1200;
  return principal * r * math.pow(1 + r, months) / (math.pow(1 + r, months) - 1);
}

/// What a year looks like for the grow-screen chart: invested vs left idle.
(List<double>, List<double>) growthSeries(double amount, double investRate, {double savingsRate = 2.75}) => (
      [for (var m = 0; m <= 12; m++) fdMaturity(amount, investRate, m)],
      [for (var m = 0; m <= 12; m++) amount * (1 + savingsRate / 1200 * m)],
    );
