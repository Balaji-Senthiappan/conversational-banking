import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/format.dart';
import '../app/theme.dart';
import '../data/models.dart';
import '../engine/assistant.dart';
import '../engine/insights.dart';
import '../state/session.dart';
import 'common.dart';

const _sheetTitle = TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: AppColors.ink);

Widget _sheetFrame(BuildContext context, List<Widget> children) => SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
      ),
    );

Widget _kv(String k, String v, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(child: Text(k, style: const TextStyle(fontSize: 14.5, color: AppColors.muted))),
        Text(v,
            style: TextStyle(
                fontSize: strong ? 17 : 14.5,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
                color: AppColors.ink)),
      ]),
    );

Future<void> _success(BuildContext context, String title, String? detail) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.page,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(color: AppColors.tealSoft, shape: BoxShape.circle),
            child: const Icon(Icons.check, color: AppColors.teal, size: 32),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: _sheetTitle),
          if (detail != null) ...[
            const SizedBox(height: 8),
            Text(detail, textAlign: TextAlign.center, style: AppText.note),
          ],
          const SizedBox(height: 20),
          PrimaryButton('Done', onTap: () => Navigator.of(ctx).pop()),
        ]),
      ),
    );

// ------------------------------------------------------------------ payments

Future<void> showPaySheet(BuildContext context, List<Obligation> items) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final session = SessionScope.of(ctx);
      final account = session.data.primaryAccount;
      final total = items.fold<double>(0, (s, o) => s + o.amount);
      final short = total > account.availableBalance;
      final rec = session.insights.recommend();
      return _sheetFrame(ctx, [
        Text(items.length == 1 ? 'Pay ${items.first.payee.name}' : 'Pay all ${items.length}', style: _sheetTitle),
        const SizedBox(height: 12),
        for (final o in items) _kv(o.payee.name, inr(o.amount)),
        const Divider(height: 24),
        _kv('Total', inr(total), strong: true),
        _kv(
          'From ${account.accountType == AccountType.savings ? 'Savings' : 'Current'} ${account.maskedNumber}',
          'Available ${inr(account.availableBalance)}',
        ),
        const SizedBox(height: 16),
        if (short) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.amberSoft, borderRadius: BorderRadius.circular(12)),
            child: Text('You are ${inr(total - account.availableBalance)} short for this.',
                style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 12),
          if (rec.kind == RecommendationKind.credit)
            PrimaryButton('See credit options', onTap: () {
              Navigator.of(ctx).pop();
              session.go(AppScreen.grow);
            }),
        ] else
          ProcessingButton('Confirm with MPIN (demo)', processingLabel: 'Processing payment…', onConfirm: () async {
            final result = session.pay(items);
            Navigator.of(ctx).pop();
            showResult(context, result.message, detail: result.detail);
            if (result.ok) session.finishAction();
          }),
      ]);
    },
  );
}

// -------------------------------------------------------- deposits and credit

Future<void> showOfferSheet(BuildContext context, OfferLine offer, double amount) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _OfferSheet(offer: offer, initialAmount: amount, hostContext: context),
  );
}

class _OfferSheet extends StatefulWidget {
  final OfferLine offer;
  final double initialAmount;
  final BuildContext hostContext;
  const _OfferSheet({required this.offer, required this.initialAmount, required this.hostContext});

  @override
  State<_OfferSheet> createState() => _OfferSheetState();
}

class _OfferSheetState extends State<_OfferSheet> {
  late double _amount = widget.initialAmount;
  late int _months = widget.offer.product.defaultTenureMonths;

  ProductOffer get p => widget.offer.product;
  bool get _isCredit => p.kind == ProductKind.credit;

  double get _step => switch (p.code) {
        'RD' => 1000,
        'BIZ_OD' || 'WC_LOAN' || 'BIZ_LOAN' => 50000,
        _ => 10000,
      };

  List<int> get _tenures => switch (p.code) {
        'SWEEP_FD' || 'BIZ_OD' => const [],
        'FD_1Y' => const [6, 12, 24, 36],
        'RD' => const [12, 24, 36, 60],
        'WC_LOAN' => const [6, 12, 18, 24],
        _ => const [24, 36, 48],
      };

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final rec = session.insights.recommend();
    final account = session.data.primaryAccount;
    final maxAmount = switch (p.code) {
      'RD' => 50000.0,
      'SWEEP_FD' || 'FD_1Y' => math.max(_step, ((account.currentBalance - 5000) / _step).floorToDouble() * _step),
      'BIZ_LOAN' => widget.offer.amount,
      _ => widget.offer.amount,
    };
    final amount = _amount.clamp(_step, maxAmount).toDouble();
    final isPrimary = rec.offers.isNotEmpty && rec.offers.first.product.code == p.code;

    final details = <Widget>[];
    if (!_isCredit) {
      final maturity = p.code == 'RD' ? rdMaturity(amount, p.rate, _months) : fdMaturity(amount, p.rate, _months);
      final maturityDate = DateTime(session.insights.today.year, session.insights.today.month + _months,
          session.insights.today.day);
      details.addAll([
        _kv('Rate', '${pct(p.rate)} p.a.'),
        _kv(p.code == 'RD' ? 'You pay' : 'Tenure',
            p.code == 'RD' ? '${inr(amount * _months)} over $_months months' : '$_months months'),
        _kv('Matures on', longDate(maturityDate)),
        _kv('Maturity value', inr(maturity), strong: true),
        if (p.code == 'SWEEP_FD')
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Renews automatically. If your savings run short, it breaks in ₹1,000 units to cover them.',
                style: AppText.note),
          ),
      ]);
    } else if (p.code == 'BIZ_OD') {
      final interest = rec.shortfall * p.rate / 100 * rec.daysShort / 365;
      details.addAll([
        _kv('Rate', '${pct(p.rate)} p.a. on what you use'),
        _kv('Valid for', '12 months, renewable'),
        _kv('Credit score', '${session.data.profile.creditScore} · ${session.data.profile.creditBureau}'),
        if (rec.shortfall > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                'Covering the ${inr(rec.shortfall)} dip for about ${rec.daysShort} days costs roughly ${inr(interest)}.',
                style: AppText.note),
          ),
      ]);
    } else {
      details.addAll([
        _kv('Rate', '${pct(p.rate)} p.a.'),
        _kv('EMI', '${inr(emi(amount, p.rate, _months))} × $_months', strong: true),
        _kv('Credit score', '${session.data.profile.creditScore} · ${session.data.profile.creditBureau}'),
      ]);
    }

    return _sheetFrame(context, [
      Text(p.name, style: _sheetTitle),
      const SizedBox(height: 4),
      Text(widget.offer.note, style: AppText.note),
      const SizedBox(height: 18),
      Text(
          switch (p.code) {
            'RD' => 'Monthly instalment',
            'BIZ_OD' => 'Overdraft limit',
            _ when _isCredit => 'Loan amount',
            _ => 'Amount',
          },
          style: const TextStyle(fontSize: 13, color: AppColors.muted)),
      const SizedBox(height: 6),
      Row(children: [
        _StepButton(Icons.remove, amount > _step ? () => setState(() => _amount = amount - _step) : null),
        Expanded(
          child: Text(inr(amount),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.ink)),
        ),
        _StepButton(Icons.add, amount < maxAmount ? () => setState(() => _amount = amount + _step) : null),
      ]),
      if (_isCredit)
        Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Pre-approved up to ${inr(maxAmount)}', style: AppText.note),
          ),
        ),
      if (_tenures.isNotEmpty) ...[
        const SizedBox(height: 16),
        const Text('Tenure', style: TextStyle(fontSize: 13, color: AppColors.muted)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final m in _tenures)
            ChoiceChip(
              label: Text(m % 12 == 0 ? '${m ~/ 12} yr' : '$m mo'),
              selected: _months == m,
              onSelected: (_) => setState(() => _months = m),
              selectedColor: AppColors.tealSoft,
              side: const BorderSide(color: AppColors.border),
              showCheckmark: false,
            ),
        ]),
      ],
      const SizedBox(height: 14),
      ...details,
      if (isPrimary && rec.workings.isNotEmpty)
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: const Text('How we worked this out',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.teal)),
            children: [
              for (final w in rec.workings)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text('•  $w', style: AppText.note),
                ),
            ],
          ),
        )
      else
        const SizedBox(height: 16),
      ProcessingButton(
        _isCredit ? 'Accept with e-sign (demo)' : 'Confirm with MPIN (demo)',
        processingLabel: _isCredit ? 'Setting up your credit…' : 'Booking your deposit…',
        onConfirm: () async {
          final result = _isCredit
              ? session.acceptCredit(p, amount, _months)
              : session.bookDeposit(p, amount, _months);
          Navigator.of(context).pop();
          if (result.ok) {
            await _success(widget.hostContext, result.message, result.detail);
            session.finishAction();
          } else {
            showResult(widget.hostContext, result.message, detail: result.detail);
          }
        },
      ),
      const SizedBox(height: 8),
      const Center(child: Text('Illustrative rates for the demo', style: TextStyle(fontSize: 12, color: AppColors.faint))),
    ]);
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepButton(this.icon, this.onTap);

  @override
  Widget build(BuildContext context) => Material(
        color: onTap == null ? AppColors.chip : AppColors.tealSoft,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: onTap == null ? AppColors.faint : AppColors.tealDark),
          ),
        ),
      );
}
