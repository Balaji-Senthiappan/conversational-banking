import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Speech-to-text behind one interface, so a self-hosted engine can replace the
/// device recogniser later without touching the UI.
abstract class SpeechInput {
  /// Starts listening. [onWords] gets the live transcript; [onDone] gets the
  /// final text ('' when nothing was heard). Throws [SpeechUnavailable] if this
  /// engine cannot run here.
  Future<void> start({required void Function(String words) onWords, required void Function(String text) onDone});

  Future<void> stop();
}

class SpeechUnavailable implements Exception {
  final String reason;
  const SpeechUnavailable(this.reason);

  @override
  String toString() => reason;
}

/// Android SpeechRecognizer, iOS Speech framework, Web Speech API in Chrome/Edge.
class DeviceSpeechInput implements SpeechInput {
  static const preferredLocales = ['en_IN', 'en-IN'];

  final SpeechToText _stt = SpeechToText();
  bool? _ready;
  String? _localeId;
  String _words = '';
  void Function(String)? _onDone;

  Future<void> _ensureReady() async {
    _ready ??= await _stt.initialize(onError: _handleError, onStatus: _handleStatus);
    if (_ready != true) {
      throw const SpeechUnavailable('Speech recognition is not available on this device or browser');
    }
    if (_localeId == null) {
      final locales = await _stt.locales();
      _localeId = locales
              .map((l) => l.localeId)
              .where(preferredLocales.contains)
              .firstOrNull ??
          (await _stt.systemLocale())?.localeId;
    }
  }

  @override
  Future<void> start({required void Function(String) onWords, required void Function(String) onDone}) async {
    await _ensureReady();
    _words = '';
    _onDone = onDone;
    await _stt.listen(
      onResult: (SpeechRecognitionResult r) {
        _words = r.recognizedWords;
        onWords(_words);
        if (r.finalResult) _finish();
      },
      listenOptions: SpeechListenOptions(
        localeId: _localeId,
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.confirmation,
      ),
    );
  }

  @override
  Future<void> stop() async {
    await _stt.stop();
    // Some platforms report no final result after a manual stop.
    Future<void>.delayed(const Duration(milliseconds: 600), _finish);
  }

  void _finish() {
    final done = _onDone;
    _onDone = null;
    done?.call(_words.trim());
  }

  void _handleStatus(String status) {
    if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) {
      Future<void>.delayed(const Duration(milliseconds: 400), _finish);
    }
  }

  void _handleError(SpeechRecognitionError error) {
    // error_no_match / error_speech_timeout: nothing heard. Finish with what we have.
    _finish();
  }
}

/// The demo-safe voice: "hears" a fixed phrase. Used on long-press, or when the
/// device has no recogniser.
class SimulatedSpeechInput implements SpeechInput {
  final String Function() phrase;
  Timer? _timer;

  SimulatedSpeechInput(this.phrase);

  @override
  Future<void> start({required void Function(String) onWords, required void Function(String) onDone}) async {
    final words = phrase().split(' ');
    var shown = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 220), (t) {
      shown++;
      onWords(words.take(shown).join(' '));
      if (shown >= words.length) {
        t.cancel();
        Future<void>.delayed(const Duration(milliseconds: 500), () => onDone(words.join(' ')));
      }
    });
  }

  @override
  Future<void> stop() async => _timer?.cancel();
}
