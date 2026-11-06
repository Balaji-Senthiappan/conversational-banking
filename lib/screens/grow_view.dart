import 'package:flutter/material.dart';

import '../app/format.dart';
import '../app/theme.dart';
import '../data/models.dart';
import '../engine/assistant.dart';
import '../engine/insights.dart';
import '../state/session.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/sheets.dart';

/// Screen 2: the recommendation. Deposit for surplus, credit for a projected shortfall.
class GrowView extends StatelessWidget {
  const GrowView({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final rec = session.insights.recommend();

    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 16), children: [
      Eyebrow(rec.eyebrow),
      const SizedBox(height: 12),
      Text(rec.headline, style: AppText.headline),
      const SizedBox(height: 10),
      Text(rec.subline, style: AppText.sub),
      const SizedBox(height: 16),
      if (rec.kind == RecommendationKind.invest) _growthCard(rec),
      if (rec.kind == RecommendationKind.credit || rec.kind == RecommendationKind.covered)
        _cashflowCard(rec, session.insights.overdraftLimit),
      if (rec.kind == RecommendationKind.working) _holdingsCard(session),
      const SizedBox(height: 14),
      for (final offer in rec.offers) ...[
        OutlineCard(
          onTap: () => showOfferSheet(context, offer, offer.amount),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(offer.product.name, style: AppText.cardTitle)),
              Text('${pct(offer.product.rate)} p.a.', style: AppText.note),
            ]),
            const SizedBox(height: 6),
            Text(offer.note, style: AppText.note),
          ]),
        ),
        const SizedBox(height: 14),
      ],
      if (rec.offers.isNotEmpty) ...[
        PrimaryButton(rec.primaryCta, onTap: () => showOfferSheet(context, rec.offers.first, rec.amount)),
        const SizedBox(height: 14),
        SoftButton(rec.secondaryCta, onTap: () {
          showResult(context, 'Reminder set for ${rec.remindOn}');
          session.go(AppScreen.today);
        }),
      ] else
        SoftButton('Back to today', onTap: () => session.go(AppScreen.today)),
    ]);
  }

  Widget _growthCard(Recommendation rec) {
    final sweep = rec.offers.first;
    final (invested, idle) = growthSeries(rec.amount, sweep.product.rate);
    return OutlineCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 8),
        GrowthChart(invested: invested, idle: idle),
        const SizedBox(height: 10),
        const Row(children: [
          Text('Today', style: AppText.note),
          Spacer(),
          Text('12 months', style: AppText.note),
        ]),
        const SizedBox(height: 8),
        const Text('Illustrative only. Teal: invested. Grey: left idle.', style: AppText.note),
      ]),
    );
  }

  Widget _cashflowCard(Recommendation rec, double odLimit) {
    return OutlineCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 8),
        CashflowChart(balances: rec.projection, overdraftLimit: odLimit),
        const SizedBox(height: 10),
        const Row(children: [
          Text('Today', style: AppText.note),
          Spacer(),
          Text('30 days', style: AppText.note),
        ]),
        const SizedBox(height: 8),
        Text(
          odLimit > 0
              ? 'Projected balance. Shaded: below zero, covered by your overdraft (teal dots).'
              : 'Projected balance from usual payments and expected receipts. Shaded: below zero.',
          style: AppText.note,
        ),
      ]),
    );
  }

  Widget _holdingsCard(BankSession session) {
    final fds = session.data.fixedDeposits;
    return OutlineCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
                session.data.primaryAccount.accountType == AccountType.savings ? 'Savings balance' : 'Current account',
                style: AppText.body),
          ),
          Text(inr(session.data.primaryAccount.currentBalance), style: AppText.cardTitle),
        ]),
        for (final fd in fds) ...[
          const Divider(height: 22),
          Row(children: [
            Expanded(child: Text(fd.productCode == 'RD' ? 'Recurring Deposit' : 'FD ${fd.fdNumber}', style: AppText.body)),
            Text(inr(fd.productCode == 'RD' ? fd.principalAmount / fd.tenureMonths : fd.principalAmount),
                style: AppText.cardTitle),
          ]),
          const SizedBox(height: 4),
          Text('${pct(fd.interestRate)} p.a. · matures ${longDate(fd.maturityDate)} at ${inr(fd.maturityAmount)}',
              style: AppText.note),
        ],
      ]),
    );
  }
}
