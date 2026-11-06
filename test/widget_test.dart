import 'package:bank_cx_mock/app/clock.dart';
import 'package:bank_cx_mock/data/mock_bank.dart';
import 'package:bank_cx_mock/engine/assistant.dart';
import 'package:bank_cx_mock/engine/insights.dart';
import 'package:bank_cx_mock/engine/voice_agent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final api = MockBankApi();
  // The figures below are the signed-off screens, which are set on 5 Nov 2026.
  setUp(() => clock = () => DateTime(2026, 11, 5, 8, 30));

  test('Priya: today items, idle balance and sweep FD match the signed-off screens', () async {
    final ins = CustomerInsights(await api.loadCustomer('CUST-1001'));
    final today = ins.todayItems();
    expect(today.map((o) => o.payee.name), ['Airtel postpaid', 'Amma', 'Credit card bill']);
    expect(today.map((o) => o.reason), [
      'Paid on the 5th for 8 months running',
      'Monthly, usually between the 1st and 5th',
      'Due 9 Nov. You usually pay in full',
    ]);
    expect(today.fold<double>(0, (s, o) => s + o.amount), 28229);

    final rec = ins.recommend();
    expect(rec.kind, RecommendationKind.invest);
    expect(rec.headline, '₹1,85,000 has sat idle in savings for 41 days.');
    expect(rec.primaryCta, 'Move ₹1,50,000 to Auto-sweep FD');
    expect(rec.offers[2].note, '₹10,000 a month, built from salary');

    final spend = ins.spendSummary();
    expect(spend.total, 46820);
    expect(spend.changePct.round(), 12);
    expect(spend.categories.take(4).map((c) => c.name), ['Food', 'Bills', 'Travel', 'Shopping']);
    expect(spend.insight!.primaryLabel, 'Set ₹8,000 cap');
    expect(spend.insight!.secondaryLabel, 'Show weekends');
  });

  test('Rajesh: projected shortfall leads to an overdraft offer', () async {
    final ins = CustomerInsights(await api.loadCustomer('CUST-2001'));
    expect(ins.todayItems().map((o) => o.payee.name).toSet(), {'Staff salaries', 'Sharma Yarns', 'TNEB electricity'});
    final rec = ins.recommend();
    expect(rec.kind, RecommendationKind.credit);
    expect(rec.amount, 150000);
    expect(rec.shortfall, greaterThan(100000));
  });

  test('Assistant maps phrases to actions', () async {
    final ins = CustomerInsights(await api.loadCustomer('CUST-1001'));
    expect(interpret('Pay Amma', ins, unpaidToday: ins.todayItems()), isA<PayIntent>());
    final fd = interpret('Move ₹1,50,000 to the sweep FD', ins, unpaidToday: ins.todayItems()) as OfferIntent;
    expect(fd.amount, 150000);
    expect(interpret('Where did my money go this month?', ins, unpaidToday: const []), isA<SpendIntent>());
    expect(parseAmount('put 1.5 lakh in FD'), 150000);

    // Misheard speech still finds the payee; ordinary sentences do not.
    final misheard = interpret('A Kartel.', ins, unpaidToday: ins.todayItems()) as PayIntent;
    expect(misheard.items.single.payee.name, 'Airtel postpaid');
    expect(interpret('Hello there', ins, unpaidToday: const []), isA<ReplyIntent>());
  });

  test('Realtime tool calls map to app actions with engine figures', () async {
    final ins = CustomerInsights(await api.loadCustomer('CUST-1001'));
    final cfg = voiceSessionConfig(ins, unpaidToday: ins.todayItems());
    final tools = [for (final t in cfg['tools'] as List) (t as Map)['name']];
    expect(tools, ['propose_payment', 'propose_product', 'show_spending', 'open_screen']);
    expect(cfg['instructions'], contains('Airtel postpaid'));

    final pay = resolveToolCall('propose_payment', {'payee_ids': ['P_AIRTEL']}, ins);
    expect((pay.intent as PayIntent).items.single.amount, 799);
    expect(resolveToolCall('propose_payment', {'payee_ids': ['NOBODY']}, ins).intent, isNull);

    final fd = resolveToolCall('propose_product', {'product_code': 'SWEEP_FD'}, ins);
    expect((fd.intent as OfferIntent).amount, 150000);

    final spend = resolveToolCall('show_spending', {'view': 'summary'}, ins);
    expect(spend.intent, isA<SpendIntent>());
    expect(spend.output['month_so_far'], 46820);
    expect(spend.output['change_pct'], 12);
  });

  test('Mock data follows the system clock', () async {
    clock = () => DateTime(2027, 1, 18, 19, 0);
    final ins = CustomerInsights(await api.loadCustomer('CUST-1001'));
    final spend = ins.spendSummary();
    expect(spend.total, greaterThan(0), reason: 'January so far still has spends');
    expect(ins.recommend().kind, RecommendationKind.invest);
    expect(ins.data.transactions.every((t) => !t.transactionTimestamp.isAfter(DateTime(2027, 1, 19))), isTrue);
  });
}
