import 'package:flutter/material.dart';

import '../app/format.dart';
import '../app/theme.dart';
import '../data/mock_bank.dart';
import '../engine/assistant.dart';
import '../engine/insights.dart';
import '../state/session.dart';
import '../widgets/common.dart';
import '../widgets/sheets.dart';

/// Screen 1: "Today for you".
class TodayView extends StatelessWidget {
  const TodayView({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final name = session.data.customer.firstName;
    final hour = demoToday.hour;
    final greeting = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');
    final unpaid = session.unpaidToday;
    final total = unpaid.fold<double>(0, (s, o) => s + o.amount);
    final rec = session.insights.recommend();

    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 16), children: [
      const Eyebrow('Today for you'),
      const SizedBox(height: 12),
      Text("$greeting, $name. It's the ${ordinal(demoToday.day)}.", style: AppText.headline),
      const SizedBox(height: 10),
      Text(
        session.todayPlan.isEmpty
            ? 'Nothing is due around now.'
            : session.visibleToday.isEmpty
                ? 'All done. Everything due around now is paid.'
                : "Here's what you usually do around now. One tap each.",
        style: AppText.sub,
      ),
      const SizedBox(height: 16),
      for (final o in session.visibleToday) ...[
        _ObligationCard(
          o,
          paid: session.paidPayees.contains(o.payee.payeeId),
          onClose: () => session.dismissPaid(o.payee.payeeId),
        ),
        const SizedBox(height: 14),
      ],
      if (session.todayPlan.isNotEmpty)
        PrimaryButton(
          unpaid.isEmpty ? 'All done for today' : 'Do all ${unpaid.length} · ${inr(total)}',
          onTap: unpaid.isEmpty ? null : () => showPaySheet(context, unpaid),
        ),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: [
        PillChip('Spent this month', onTap: () => session.go(AppScreen.ask)),
        PillChip(rec.kind == RecommendationKind.credit || rec.kind == RecommendationKind.covered ? 'Cash flow' : 'Move money',
            onTap: () => session.go(AppScreen.grow)),
        PillChip('Add a payee', onTap: () => showResult(context, 'Adding payees is not part of this demo')),
      ]),
    ]);
  }
}

class _ObligationCard extends StatelessWidget {
  final Obligation o;
  final bool paid;
  /// Removes the card from Today. Only offered once it is paid.
  final VoidCallback onClose;
  const _ObligationCard(this.o, {required this.paid, required this.onClose});

  @override
  Widget build(BuildContext context) => OutlineCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(o.payee.name, style: AppText.cardTitle)),
            Text(inr(o.amount), style: AppText.cardTitle),
            if (paid) ...[
              const SizedBox(width: 4),
              // Close a paid card; compact so the row keeps its height.
              IconButton(
                tooltip: 'Close',
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 20, color: AppColors.muted),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 32, height: 28),
              ),
            ],
          ]),
          const SizedBox(height: 6),
          Text(o.reason, style: AppText.note),
          const SizedBox(height: 12),
          paid
              ? const SoftButton('Paid', icon: Icons.check)
              : SoftButton(o.actionLabel, onTap: () => showPaySheet(context, [o])),
        ]),
      );
}
