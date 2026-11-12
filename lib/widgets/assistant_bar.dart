import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../speech/realtime_voice.dart';
import '../speech/speech_input.dart';
import 'common.dart';

/// One recogniser for the whole app: initialising it is slow and asks for permission.
final _deviceSpeech = DeviceSpeechInput();

/// "Speak or type. One assistant, two ways to ask." Pinned to the bottom of every screen.
/// Tap the mic to speak. With a token service configured (REALTIME_TOKEN_URL) that is a
/// live conversation with the realtime model, which acts through [onToolCall]; otherwise
/// the device recogniser. Long-press for the demo voice, which "hears" [voiceSample]; it is
/// also the fallback when neither is available.
class AssistantBar extends StatefulWidget {
  final String hint;
  final String voiceSample;
  /// Returns a short message to show above the input (e.g. "Didn't get that"), or null.
  final String? Function(String text) onSubmit;
  /// Realtime voice: the session config (instructions, context, tools) and the tool handler.
  final Map<String, dynamic> Function()? realtimeSession;
  final Future<Map<String, dynamic>> Function(String name, Map<String, dynamic> args)? onToolCall;
  /// The customer's voice accent as a language tag, from their profile (e.g. "en-IN").
  final String voiceLocale;

  const AssistantBar({
    super.key,
    required this.hint,
    required this.voiceSample,
    required this.onSubmit,
    this.realtimeSession,
    this.onToolCall,
    this.voiceLocale = 'en-IN',
  });

  @override
  State<AssistantBar> createState() => _AssistantBarState();
}

class _AssistantBarState extends State<AssistantBar> {
  final _controller = TextEditingController();
  late final _demoSpeech = SimulatedSpeechInput(() => widget.voiceSample);
  SpeechInput? _active;
  String? _status;
  RealtimeVoice? _rt;

  bool get _rtListening => _rt?.state.value == RealtimeState.listening;
  bool get _listening => _active != null || _rtListening;

  @override
  void initState() {
    super.initState();
    if (realtimeConfigured && widget.realtimeSession != null && widget.onToolCall != null) _startRealtime();
  }

  /// Connects in the background with the mic muted, so a tap starts listening at once.
  void _startRealtime() {
    final rt = _rt = RealtimeVoice()
      ..onUserSaid = (text) {
        if (mounted) _controller.text = text;
      }
      ..onAssistantText = (text, done) {
        if (mounted) setState(() => _status = text);
      }
      ..onToolCall = (name, args) async {
        // A confirmation sheet is about to open: stop listening so speech can't act behind it.
        if (name.startsWith('propose_')) _rt?.mute();
        final out = await widget.onToolCall!(name, args);
        if (mounted) _controller.clear();
        return out;
      }
      ..onError = (message) {
        debugPrint('Realtime voice: $message');
        if (mounted && _rt?.state.value == RealtimeState.failed) {
          setState(() => _status = 'Live voice is unavailable ($message). Using the device recogniser.');
        }
      };
    rt.state.addListener(() {
      if (mounted) setState(() {});
    });
    rt.connect(widget.realtimeSession!()).catchError((_) {});
  }

  @override
  void didUpdateWidget(AssistantBar old) {
    super.didUpdateWidget(old);
    if (_rt != null && widget.realtimeSession != null) _rt!.updateSession(widget.realtimeSession!());
  }

  @override
  void dispose() {
    _active?.stop();
    _rt?.close();
    _controller.dispose();
    super.dispose();
  }

  void _submit(String text) {
    if (text.trim().isEmpty) return;
    _controller.clear();
    FocusScope.of(context).unfocus();
    final feedback = widget.onSubmit(text.trim());
    if (mounted) setState(() => _status = feedback);
  }

  Future<void> _toggleMic({bool demo = false}) async {
    if (_rtListening) {
      _rt!.mute();
      setState(() => _status = null);
      return;
    }
    if (_listening) {
      await _active!.stop();
      return;
    }
    FocusScope.of(context).unfocus();
    if (!demo && (_rt?.isUsable ?? false)) {
      _rt!.listen();
      setState(() {
        _controller.clear();
        _status = 'Live voice: go ahead and speak. Tap the mic to stop.';
      });
      return;
    }
    if (!demo && _rt?.state.value == RealtimeState.connecting) {
      setState(() => _status = 'Live voice is still connecting. Using the device recogniser this time.');
    }
    try {
      _deviceSpeech.preferLocale(widget.voiceLocale);
      await _listen(demo ? _demoSpeech : _deviceSpeech);
    } on SpeechUnavailable catch (e) {
      if (!mounted) return;
      setState(() => _active = null);
      showResult(context, 'Voice is not available here', detail: '$e. Using the demo voice instead.');
      await _listen(_demoSpeech);
    } catch (e) {
      if (!mounted) return;
      setState(() => _active = null);
      showResult(context, 'Could not start the microphone', detail: '$e');
    }
  }

  Future<void> _listen(SpeechInput engine) async {
    setState(() {
      _active = engine;
      _status = engine is SimulatedSpeechInput ? 'Demo voice…' : 'Listening… tap the mic to stop';
      _controller.clear();
    });
    await engine.start(
      onWords: (words) {
        if (mounted && _listening) _controller.text = words;
      },
      onDone: (text) {
        if (!mounted) return;
        setState(() {
          _active = null;
          _status = text.isEmpty ? "Didn't catch that. Try again, or type." : null;
        });
        _submit(text);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(6)),
          child: Text((_rt?.isUsable ?? false) ? 'AI · live' : 'AI',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(_status ?? 'Speak or type. One assistant, two ways to ask.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: _listening ? AppColors.amber : AppColors.muted)),
        ),
      ]),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          border: Border.all(color: _listening ? AppColors.amber : AppColors.teal, width: 1.4),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _controller,
              readOnly: _listening,
              minLines: 1,
              maxLines: 2,
              textInputAction: TextInputAction.send,
              onSubmitted: _submit,
              onChanged: (_) {
                if (_status != null && !_listening) setState(() => _status = null);
              },
              style: const TextStyle(fontSize: 16, color: AppColors.ink),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: _listening ? 'Go ahead, I’m listening' : widget.hint,
                hintMaxLines: 2,
                hintStyle: const TextStyle(fontSize: 16, color: AppColors.muted, height: 1.3),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Tap to speak · long-press for the demo voice',
            child: Material(
              color: _listening ? AppColors.amber : AppColors.teal,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _toggleMic,
                onLongPress: _listening ? null : () => _toggleMic(demo: true),
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: Icon(_listening ? Icons.stop_rounded : Icons.mic_none, color: Colors.white, size: 24),
                ),
              ),
            ),
          ),
        ]),
      ),
    ]);
  }
}
