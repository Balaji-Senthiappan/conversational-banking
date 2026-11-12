import 'dart:convert';

import '../app/format.dart';
import '../data/models.dart';
import 'assistant.dart';
import 'insights.dart';

/// What the realtime model is told, and how its tool calls become app actions.
///
/// The model only proposes. Every tool resolves to one of the assistant's
/// intents (pay sheet, offer sheet, spend answer, screen), and the customer
/// confirms on screen. Figures in tool results come from [CustomerInsights].

/// The `session.update` payload: instructions with the customer's context, and tools.
Map<String, dynamic> voiceSessionConfig(CustomerInsights insights, {required List<Obligation> unpaidToday}) {
  final c = insights.data.customer;
  final rec = insights.recommend();
  final payees = insights.currentObligations();
  final context = {
    'customer': '${c.firstName} ${c.lastName}',
    'segment': insights.data.persona.label,
    'today': longDate(insights.today),
    'payees': [
      for (final o in payees)
        {
          'id': o.payee.payeeId,
          'name': o.payee.name,
          'amount_due': o.amount,
          'why': o.reason,
          'paid_already': !unpaidToday.any((u) => u.payee.payeeId == o.payee.payeeId) &&
              insights.todayItems().any((t) => t.payee.payeeId == o.payee.payeeId),
        }
    ],
    'recommendation': {
      'headline': rec.headline,
      'detail': rec.subline,
      'offers': [
        for (final o in rec.offers)
          {'code': o.product.code, 'name': o.product.name, 'rate_pct': o.product.rate, 'amount': o.amount, 'note': o.note}
      ],
    },
  };

  final offerCodes = [for (final o in rec.offers) o.product.code];
  return {
    'type': 'realtime',
    'instructions': '''
You are the voice assistant inside ${c.firstName}'s bank app. Speak ${insights.data.profile.voiceAccent}, warmly and briefly: one or two short sentences.

You act only through the tools. Never state an amount, rate or date that is not in the context below or in a tool result.
You cannot move money. Payment and product tools only open a confirmation screen, and the customer confirms there.
Say so plainly: "I've opened it, enter your MPIN to pay" for payments and deposits, or "tap Accept with e-sign" for credit.
Never ask for, repeat or read out the MPIN. Call tools straight away; don't announce them first.

Speech is often misheard. When what the customer says sounds like exactly one payee ("A Kartel" sounds like "Airtel postpaid"),
propose that payment directly; the confirmation screen is where they check it. Ask only if no payee, or more than one, matches.
Never invent a payee. For questions about spending, call show_spending and read out the main figure and the biggest change.
If a request has nothing to do with their banking here, say you can only help with their accounts in this app.

Context (JSON):
${jsonEncode(context)}'''
        .trim(),
    'tools': [
      {
        'type': 'function',
        'name': 'propose_payment',
        'description': 'Open the confirmation screen for paying one or more of the customer\'s usual payees. Does not pay.',
        'parameters': {
          'type': 'object',
          'properties': {
            'payee_ids': {
              'type': 'array',
              'items': {'type': 'string', 'enum': [for (final o in payees) o.payee.payeeId]},
              'description': 'One id, or several for "pay all".',
            },
          },
          'required': ['payee_ids'],
        },
      },
      if (offerCodes.isNotEmpty)
        {
          'type': 'function',
          'name': 'propose_product',
          'description': 'Open the confirmation screen for one of the recommended products (deposit or credit). Does not book it.',
          'parameters': {
            'type': 'object',
            'properties': {
              'product_code': {'type': 'string', 'enum': offerCodes},
              'amount': {'type': 'number', 'description': 'Rupees. Omit to use the recommended amount.'},
            },
            'required': ['product_code'],
          },
        },
      {
        'type': 'function',
        'name': 'show_spending',
        'description': 'Show and return the customer\'s spending this month so far.',
        'parameters': {
          'type': 'object',
          'properties': {
            'view': {'type': 'string', 'enum': [for (final v in SpendView.values) v.name]},
            'question': {'type': 'string', 'description': 'The customer\'s question, in their words.'},
          },
          'required': ['view'],
        },
      },
      {
        'type': 'function',
        'name': 'open_screen',
        'description': 'Open a screen: today (usual payments), grow (the recommendation), ask (spending chat).',
        'parameters': {
          'type': 'object',
          'properties': {
            'screen': {'type': 'string', 'enum': [for (final s in AppScreen.values) s.name]},
          },
          'required': ['screen'],
        },
      },
    ],
    'tool_choice': 'auto',
    'audio': {
      'input': {
        // A separate transcript, only so the app can show what it heard; the model
        // itself works on the audio. No fixed language on purpose: the transcript
        // should be in whatever language the customer spoke. whisper-1 guesses the
        // language per turn, and short Indian-accented English was once guessed as
        // Tamil; the payee names as keywords nudge it towards English (and keep the
        // names' spelling) without forcing it.
        // TODO(parked): whisper-1 is deprecated (shutdown announced for 26 Feb 2027).
        // Once gpt-transcribe (or gpt-live-transcribe) is deployed on the Azure
        // resource, switch to it with 'languages': ['en', 'ta'] so it only chooses
        // between the customer's languages.
        'transcription': {
          'model': 'whisper-1',
          'prompt': [for (final o in payees) o.payee.name].join(', '),
        },
        'turn_detection': {'type': 'server_vad', 'silence_duration_ms': 600},
      },
    },
  };
}

/// A tool call turned into an app action, plus the result to send back to the model.
class ToolOutcome {
  final AssistantIntent? intent;
  final Map<String, dynamic> output;
  const ToolOutcome(this.intent, this.output);
}

ToolOutcome resolveToolCall(String name, Map<String, dynamic> args, CustomerInsights insights) {
  switch (name) {
    case 'propose_payment':
      final ids = (args['payee_ids'] as List? ?? const []).cast<String>();
      final items = insights.currentObligations().where((o) => ids.contains(o.payee.payeeId)).toList();
      if (items.isEmpty) return const ToolOutcome(null, {'error': 'No matching payee. Ask the customer who to pay.'});
      return ToolOutcome(PayIntent(items), {
        'status': 'confirmation screen shown; the customer enters their MPIN on screen to pay',
        'payments': [for (final o in items) {'payee': o.payee.name, 'amount': o.amount}],
        'total': items.fold<double>(0, (s, o) => s + o.amount),
      });

    case 'propose_product':
      final rec = insights.recommend();
      final code = args['product_code'] as String?;
      final offer = rec.offers.where((o) => o.product.code == code).firstOrNull;
      if (offer == null) return const ToolOutcome(null, {'error': 'That product is not offered to this customer.'});
      final amount = (args['amount'] as num?)?.toDouble() ?? offer.amount;
      return ToolOutcome(OfferIntent(offer, amount), {
        'status': offer.product.kind == ProductKind.credit
            ? 'confirmation screen shown; the customer taps Accept with e-sign'
            : 'confirmation screen shown; the customer enters their MPIN on screen to confirm',
        'product': offer.product.name,
        'amount': amount,
        'rate_pct': offer.product.rate,
      });

    case 'show_spending':
      final view = SpendView.values.where((v) => v.name == args['view']).firstOrNull ?? SpendView.summary;
      final question = (args['question'] as String?)?.trim();
      final s = insights.spendSummary();
      final change = s.lastMonthSamePoint == 0 ? 0 : (s.total - s.lastMonthSamePoint) / s.lastMonthSamePoint * 100;
      return ToolOutcome(SpendIntent(question == null || question.isEmpty ? 'Where did my money go this month?' : question, view), {
        'month_so_far': s.total,
        'same_point_last_month': s.lastMonthSamePoint,
        'change_pct': change.round(),
        'categories': [for (final c in s.categories.take(5)) {'name': c.name, 'amount': c.amount}],
        if (s.insight != null) 'insight': s.insight!.message,
        if (s.insight != null) 'suggested_cap': s.insight!.cap,
      });

    case 'open_screen':
      final screen = AppScreen.values.where((v) => v.name == args['screen']).firstOrNull;
      if (screen == null) return const ToolOutcome(null, {'error': 'Unknown screen.'});
      return ToolOutcome(NavigateIntent(screen), {'opened': screen.name});
  }
  return ToolOutcome(null, {'error': 'Unknown tool $name.'});
}
