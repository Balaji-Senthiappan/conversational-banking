import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../data/models.dart';
import '../engine/assistant.dart';
import '../engine/insights.dart';
import '../engine/voice_agent.dart';
import '../state/session.dart';
import '../widgets/assistant_bar.dart';
import '../widgets/sheets.dart';
import 'ask_view.dart';
import 'grow_view.dart';
import 'today_view.dart';

/// No menus: three views, switched by chips, actions or the assistant.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final rec = session.insights.recommend();

    final (hint, voice) = switch (session.screen) {
      AppScreen.today => () {
          final person = session.unpaidToday.where((o) => o.payee.kind == PayeeKind.person).firstOrNull ??
              session.unpaidToday.where((o) => o.payee.kind == PayeeKind.vendor).firstOrNull ??
              session.unpaidToday.firstOrNull;
          final say = person == null ? 'Where did my money go?' : 'Pay ${person.payee.name}';
          return ('Type, or tap the mic and say “$say”', say);
        }(),
      AppScreen.grow => rec.kind == RecommendationKind.invest
          ? ('Type, or say “Move ${_amount(rec)} to the sweep FD”', 'Move ${_amount(rec)} to the sweep FD')
          : rec.kind == RecommendationKind.credit
              ? ('Type, or say “Get the overdraft”', 'Get the overdraft')
              : ('Type, or ask what is due this week', 'What is due this week?'),
      AppScreen.ask => ('Type, or tap the mic and ask a follow-up', 'Show weekends'),
    };

    return PopScope(
      canPop: session.screen == AppScreen.today,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) session.go(AppScreen.today);
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(children: [
            _Header(session),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: KeyedSubtree(
                  key: ValueKey(session.screen),
                  child: switch (session.screen) {
                    AppScreen.today => const TodayView(),
                    AppScreen.grow => const GrowView(),
                    AppScreen.ask => const AskView(),
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: AssistantBar(
                hint: hint,
                voiceSample: voice,
                voiceLocale: session.data.profile.voiceLocale, // the profile's voice accent
                onSubmit: (text) => _handle(context, session, text, voice),
                realtimeSession: () => voiceSessionConfig(session.insights, unpaidToday: session.unpaidToday),
                onToolCall: (name, args) async {
                  final outcome = resolveToolCall(name, args, session.insights);
                  if (outcome.intent != null && context.mounted) _dispatch(context, session, outcome.intent!);
                  return outcome.output;
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  static String _amount(Recommendation rec) {
    final digits = rec.primaryCta.replaceAll(RegExp(r'[^0-9₹,]'), '');
    return digits.isEmpty ? 'it' : digits;
  }

  /// Runs what the customer asked for. Returns a line for the assistant bar when
  /// the request was not understood outside the chat, so they stay where they are.
  String? _handle(BuildContext context, BankSession session, String text, String example) {
    final intent = interpret(text, session.insights, unpaidToday: session.unpaidToday);
    if (intent case ReplyIntent(:final question) when session.screen != AppScreen.ask) {
      return 'Didn’t get “$question”. Try “$example”.';
    }
    _dispatch(context, session, intent);
    return null;
  }

  /// Carries out an intent, whether it came from typed text, device speech or a realtime tool call.
  static void _dispatch(BuildContext context, BankSession session, AssistantIntent intent) {
    switch (intent) {
      case PayIntent(:final items):
        showPaySheet(context, items);
      case OfferIntent(:final offer, :final amount):
        session.go(AppScreen.grow);
        showOfferSheet(context, offer, amount);
      case NavigateIntent(:final screen):
        session.go(screen);
      case SpendIntent(:final question, :final view):
        session.ask(question, view);
      case LogoutIntent():
        session.logout();
      case ReplyIntent(:final question, :final reply):
        session.reply(question, reply);
    }
  }
}

/// Display names for CustomerProfile.spokenLanguages codes, shown in the profile menu.
/// Add a line here when a customer speaks another language (e.g. 'de': 'German').
const _languageNames = {'en': 'English', 'ta': 'Tamil', 'hi': 'Hindi'};

class _Header extends StatelessWidget {
  final BankSession session;
  const _Header(this.session);

  @override
  Widget build(BuildContext context) {
    final c = session.data.customer;
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          if (session.screen != AppScreen.today)
            IconButton(
              tooltip: 'Back to today',
              icon: const Icon(Icons.arrow_back, color: AppColors.ink),
              onPressed: () => session.go(AppScreen.today),
            ),
          const Spacer(),
          PopupMenuButton<String>(
            tooltip: 'Profile',
            color: AppColors.page,
            surfaceTintColor: Colors.transparent,
            onSelected: (v) {
              if (v == 'logout') session.logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${c.firstName} ${c.lastName}', style: AppText.cardTitle),
                  const SizedBox(height: 2),
                  Text('${session.data.persona.label} · ${session.data.persona.assignedBy}', style: AppText.note),
                  Text('Credit score ${session.data.profile.creditScore}', style: AppText.note),
                  Text('Voice: ${session.data.profile.voiceAccent}', style: AppText.note),
                  Text('Speaks: ${session.data.profile.spokenLanguages.map((c) => _languageNames[c] ?? c).join(', ')}',
                      style: AppText.note),
                ]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'logout', child: Text('Log out')),
            ],
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: CircleAvatar(
                radius: 17,
                backgroundColor: AppColors.tealSoft,
                child: Text(c.initials,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.tealDark)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
