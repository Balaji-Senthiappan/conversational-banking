import '../data/models.dart';
import 'insights.dart';

// Keyword intent matching. In the full solution this is the private LLM's job
// (intent + entities); the actions it maps to stay deterministic.

enum AppScreen { today, grow, ask }

enum SpendView { summary, compare, weekends, merchants }

sealed class AssistantIntent {
  const AssistantIntent();
}

class PayIntent extends AssistantIntent {
  final List<Obligation> items;
  const PayIntent(this.items);
}

class OfferIntent extends AssistantIntent {
  final OfferLine offer;
  final double amount;
  const OfferIntent(this.offer, this.amount);
}

class NavigateIntent extends AssistantIntent {
  final AppScreen screen;
  const NavigateIntent(this.screen);
}

class SpendIntent extends AssistantIntent {
  final String question;
  final SpendView view;
  const SpendIntent(this.question, this.view);
}

class LogoutIntent extends AssistantIntent {
  const LogoutIntent();
}

class ReplyIntent extends AssistantIntent {
  final String question;
  final String reply;
  const ReplyIntent(this.question, this.reply);
}

const _ignoredNameWords = {'bill', 'bills', 'postpaid', 'payment', 'electricity', 'credit'};

double? parseAmount(String text) {
  final t = text.toLowerCase();
  final lakh = RegExp(r'(\d+(?:\.\d+)?)\s*(?:lakh|lac)').firstMatch(t);
  if (lakh != null) return double.parse(lakh.group(1)!) * 100000;
  final k = RegExp(r'(\d+(?:\.\d+)?)\s*k\b').firstMatch(t);
  if (k != null) return double.parse(k.group(1)!) * 1000;
  double? best;
  for (final m in RegExp(r'\d[\d,]*').allMatches(t)) {
    final v = double.tryParse(m.group(0)!.replaceAll(',', ''));
    if (v != null && v >= 100 && (best == null || v > best)) best = v;
  }
  return best;
}

bool _word(String t, String w) => RegExp('\\b$w\\b').hasMatch(t);

int _editDistance(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = [i, ...List<int>.filled(b.length, 0)];
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// Speech often mishears names ("A Kartel" for "Airtel"): allow a small edit distance.
bool _soundsLike(String nameWord, String spoken) {
  if (nameWord == spoken) return true;
  if (nameWord.length >= 5) return _editDistance(nameWord, spoken) <= 2;
  if (nameWord.length == 4) return _editDistance(nameWord, spoken) <= 1;
  return false;
}

/// The obligation whose payee name appears (exactly or nearly) in the text.
Obligation? _matchPayee(String t, List<Obligation> obligations, {bool fuzzy = true}) {
  final tokens = t.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').split(RegExp(r'\s+')).where((w) => w.length >= 3).toList();
  for (final o in obligations) {
    if (o.payee.kind == PayeeKind.card && t.contains('card')) return o;
    final words =
        o.payee.name.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length >= 3 && !_ignoredNameWords.contains(w));
    if (words.any(t.contains)) return o;
  }
  if (!fuzzy) return null;
  for (final o in obligations) {
    final words =
        o.payee.name.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length >= 4 && !_ignoredNameWords.contains(w));
    if (words.any((w) => tokens.any((s) => _soundsLike(w, s)))) return o;
  }
  return null;
}

AssistantIntent interpret(String input, CustomerInsights insights, {required List<Obligation> unpaidToday}) {
  final question = input.trim();
  final t = question.toLowerCase();
  final rec = insights.recommend();

  if (t.contains('log out') || t.contains('logout') || t.contains('sign out')) return const LogoutIntent();

  final wantsPay = ['pay', 'send', 'transfer', 'settle'].any((w) => _word(t, w));
  if (wantsPay && (t.contains(' all') || t.contains('everything'))) {
    return unpaidToday.isEmpty
        ? ReplyIntent(question, 'Everything due around now is already paid.')
        : PayIntent(unpaidToday);
  }
  final obligations = insights.currentObligations();
  if (wantsPay || _word(t, 'do')) {
    final o = _matchPayee(t, obligations);
    if (o != null) return PayIntent([o]);
  }

  OfferLine? offer(String code) {
    for (final o in rec.offers) {
      if (o.product.code == code) return o;
    }
    return null;
  }

  AssistantIntent productIntent(String code) {
    final o = offer(code);
    if (o == null) {
      return ReplyIntent(
        question,
        rec.offers.isEmpty
            ? '${rec.headline} ${rec.subline}'
            : 'Based on your balances and dues, I would start with: ${rec.primaryCta}.',
      );
    }
    final asked = parseAmount(t);
    return OfferIntent(o, asked ?? o.amount);
  }

  if (t.contains('sweep')) return productIntent('SWEEP_FD');
  if (_word(t, 'rd') || t.contains('recurring')) return productIntent('RD');
  if (_word(t, 'fd') || t.contains('fixed deposit') || t.contains('deposit')) return productIntent('FD_1Y');
  if (t.contains('overdraft') || _word(t, 'od')) return productIntent('BIZ_OD');
  if (t.contains('working capital')) return productIntent('WC_LOAN');
  if (t.contains('business loan')) return productIntent('BIZ_LOAN');

  if (t.contains('weekend')) return SpendIntent(question, SpendView.weekends);
  if (t.contains('compare') || t.contains('last month')) return SpendIntent(question, SpendView.compare);
  if (t.contains('merchant') || t.contains('vendor') || t.contains('by supplier')) {
    return SpendIntent(question, SpendView.merchants);
  }
  if (['spent', 'spend', 'spending', 'money go', 'where did'].any(t.contains)) {
    return SpendIntent(question, SpendView.summary);
  }

  // Just a payee's name ("Airtel") means pay it. Near-matches only for short
  // utterances, so a sentence like "how many years" never pays Sharma Yarns.
  final short = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length <= 3;
  final named = _matchPayee(t, obligations, fuzzy: short);
  if (named != null) return PayIntent([named]);

  if (['loan', 'invest', 'idle', 'save', 'saving', 'move money', 'grow', 'cash flow', 'short', 'credit']
      .any(t.contains)) {
    return const NavigateIntent(AppScreen.grow);
  }
  if (['home', 'today', 'due', 'bills'].any(t.contains)) return const NavigateIntent(AppScreen.today);

  return ReplyIntent(
    question,
    'In this demo I can pay your usual payments, book deposits, set up credit and explain your spends. '
    'Try “Where did my money go this month?”',
  );
}
