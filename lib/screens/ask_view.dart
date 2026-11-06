import 'package:flutter/material.dart';

import '../app/format.dart';
import '../app/theme.dart';
import '../engine/assistant.dart';
import '../engine/insights.dart';
import '../state/session.dart';
import '../widgets/common.dart';

/// Screen 3: "Ask". A short conversation; each answer is built from the spend engine.
class AskView extends StatefulWidget {
  const AskView({super.key});

  @override
  State<AskView> createState() => _AskViewState();
}

class _AskViewState extends State<AskView> {
  final _scroll = ScrollController();
  int _seen = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final turns = session.askTurns;
    if (turns.length != _seen) {
      _seen = turns.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      });
    }
    return ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 16), children: [
      const Eyebrow('Ask'),
      const SizedBox(height: 12),
      for (var i = 0; i < turns.length; i++) ...[
        _UserBubble(turns[i].question),
        const SizedBox(height: 14),
        _Answer(turns[i], latest: i == turns.length - 1),
        const SizedBox(height: 22),
      ],
    ]);
  }
}

class _UserBubble extends StatelessWidget {
  final String text;
  const _UserBubble(this.text);

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 290),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 15.5)),
        ),
      );
}

class _Answer extends StatelessWidget {
  final AskTurn turn;
  final bool latest;
  const _Answer(this.turn, {required this.latest});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final ins = session.insights;
    final summary = ins.spendSummary();
    if (turn.view == null) return Text(turn.reply ?? '', style: AppText.body);

    return switch (turn.view!) {
      SpendView.summary => _summary(context, session, summary),
      SpendView.compare => _compare(summary),
      SpendView.weekends => _weekends(ins, summary),
      SpendView.merchants => _merchants(ins, summary),
    };
  }

  Widget _summary(BuildContext context, BankSession session, SpendSummary s) {
    final top = s.categories.take(4).toList();
    final maxAmount = top.isEmpty ? 1.0 : top.first.amount;
    final change = s.changePct.round();
    final insight = s.insight;
    final capSet = insight != null && session.caps.contains(insight.category);
    final rec = session.insights.recommend();
    final lastMonth = DateTime(s.today.year, s.today.month - 1, 1);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      OutlineCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${monthName(s.today)} so far', style: AppText.note),
          const SizedBox(height: 6),
          Text('${inr(s.total)} spent', style: AppText.headline),
          const SizedBox(height: 8),
          Text(
            change == 0
                ? 'About the same as ${monthName(lastMonth)} at this point'
                : '${change.abs()}% ${change > 0 ? 'more' : 'less'} than ${monthName(lastMonth)} at this point',
            style: AppText.note,
          ),
          const SizedBox(height: 10),
          for (final c in top) BarRow(label: c.name, value: inr(c.amount), fraction: c.amount / maxAmount),
        ]),
      ),
      if (insight != null && latest) ...[
        const SizedBox(height: 16),
        Text(insight.message, style: AppText.body),
        const SizedBox(height: 14),
        Row(children: [
          capSet
              ? SoftButton(insight.primaryLabel.replaceFirst('Set ', '').replaceFirst(' cap', ' cap set')
                      .replaceFirst(' alert', ' alert set'),
                  expand: false, icon: Icons.check)
              : PrimaryButton(insight.primaryLabel, expand: false, onTap: () {
                  session.setCap(insight.category);
                  showResult(context, '${insight.primaryLabel.replaceFirst('Set ', '')} on ${insight.category}',
                      detail: 'We will nudge you at 80% and when you cross it.');
                }),
          const SizedBox(width: 10),
          Flexible(
            child: SoftButton(insight.secondaryLabel,
                expand: false,
                onTap: () => session.ask(insight.secondaryLabel,
                    insight.mostlyWeekends && !session.insights.isBusiness ? SpendView.weekends : SpendView.merchants)),
          ),
        ]),
      ],
      if (latest) ...[
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          PillChip('Compare with last month', onTap: () => session.ask('Compare with last month', SpendView.compare)),
          PillChip(
            rec.kind == RecommendationKind.invest ? 'Move savings aside' : 'Check cash flow',
            onTap: () => session.go(AppScreen.grow),
          ),
        ]),
      ],
    ]);
  }

  Widget _compare(SpendSummary s) {
    final lastMonth = DateTime(s.today.year, s.today.month - 1, 1);
    return OutlineCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('First ${s.today.day} days: ${monthName(lastMonth)} vs ${monthName(s.today)}', style: AppText.note),
        const SizedBox(height: 10),
        for (final c in s.categories)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Expanded(child: Text(c.name, style: const TextStyle(fontSize: 14, color: AppColors.muted))),
              SizedBox(width: 80, child: Text(inr(c.lastMonthSamePoint), textAlign: TextAlign.right, style: AppText.note)),
              SizedBox(
                width: 84,
                child: Text(inr(c.amount),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
              ),
            ]),
          ),
        const Divider(height: 20),
        Row(children: [
          const Expanded(child: Text('Total', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
          SizedBox(width: 80, child: Text(inr(s.lastMonthSamePoint), textAlign: TextAlign.right, style: AppText.note)),
          SizedBox(
            width: 84,
            child: Text(inr(s.total),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
          ),
        ]),
      ]),
    );
  }

  Widget _weekends(CustomerInsights ins, SpendSummary s) {
    final category = s.insight?.category ?? (s.categories.isEmpty ? 'Food' : s.categories.first.name);
    final (weekend, weekday) = ins.weekendSplit(category);
    final total = weekend + weekday;
    return OutlineCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$category, ${monthName(s.today)} so far', style: AppText.note),
        const SizedBox(height: 10),
        BarRow(label: 'Weekends', value: inr(weekend), fraction: total == 0 ? 0 : weekend / total, labelWidth: 84),
        BarRow(label: 'Weekdays', value: inr(weekday), fraction: total == 0 ? 0 : weekday / total, labelWidth: 84),
        const SizedBox(height: 8),
        Text(
          total == 0 ? 'No spends yet.' : '${(weekend / total * 100).round()}% of it on weekends.',
          style: AppText.note,
        ),
      ]),
    );
  }

  Widget _merchants(CustomerInsights ins, SpendSummary s) {
    final category = s.insight?.category ?? (s.categories.isEmpty ? 'Food' : s.categories.first.name);
    final rows = ins.byCounterparty(category);
    final maxAmount = rows.isEmpty ? 1.0 : rows.first.$2;
    return OutlineCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$category by ${ins.isBusiness ? 'vendor' : 'merchant'}, ${monthName(s.today)} so far', style: AppText.note),
        const SizedBox(height: 10),
        for (final (name, amount) in rows)
          BarRow(label: name, value: inr(amount), fraction: amount / maxAmount, labelWidth: 120),
      ]),
    );
  }
}
