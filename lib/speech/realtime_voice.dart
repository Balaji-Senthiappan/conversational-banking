import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

/// Token service base URL, e.g. http://localhost:8091 (web) or http://10.0.2.2:8091 (Android emulator).
/// Empty means realtime voice is off and the app uses the device recogniser.
const realtimeTokenUrl = String.fromEnvironment('REALTIME_TOKEN_URL');
bool get realtimeConfigured => realtimeTokenUrl.isNotEmpty;

enum RealtimeState { idle, connecting, ready, listening, failed, closed }

/// Live voice with the Azure OpenAI Realtime model over WebRTC.
///
/// The token service mints a short-lived key, so the Azure credential never
/// reaches the device. Audio goes both ways on the peer connection (with the
/// platform's echo cancellation). Events, including tool calls, go over the
/// `oai-events` data channel. The mic track stays disabled until [listen].
class RealtimeVoice {
  final ValueNotifier<RealtimeState> state = ValueNotifier(RealtimeState.idle);

  /// Final transcript of what the customer said, when the model reports it.
  void Function(String text)? onUserSaid;

  /// Assistant speech as text, streamed. `done` is true at the end of a reply.
  void Function(String text, bool done)? onAssistantText;

  /// A tool call. Return the JSON-able result to send back to the model.
  Future<Map<String, dynamic>> Function(String name, Map<String, dynamic> args)? onToolCall;

  void Function(String message)? onError;

  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  MediaStream? _mic;
  RTCVideoRenderer? _speaker; // plays remote audio on web; native plays it by itself
  Map<String, dynamic>? _session;
  String _reply = '';
  final _pendingCalls = <Map<String, dynamic>>[];
  Completer<void>? _open;

  bool get isUsable => state.value == RealtimeState.ready || state.value == RealtimeState.listening;

  /// Connects in the background with the mic muted. Safe to call again.
  //
  // TODO(parked, low priority): connecting is slow and sometimes fails.
  // Seen in testing (Nov 2026): "AI · live" can take 15–30 s after sign-in, one start
  // reported a connection error, and live voice only came up after a transaction.
  // Until then the mic quietly uses the device recogniser, which never speaks back.
  // To look at:
  //   - start connecting during the sign-in loading checklist, not after it;
  //   - retry once with a fresh key when the connection fails;
  //   - keep "still connecting, using the device recogniser" visible while listening;
  //   - log how long each stage takes (key, getUserMedia, SDP exchange, data channel).
  Future<void> connect(Map<String, dynamic> session) async {
    _session = session;
    if (state.value == RealtimeState.connecting || isUsable) return;
    state.value = RealtimeState.connecting;
    try {
      final res = await http.post(Uri.parse('$realtimeTokenUrl/realtime/session')).timeout(const Duration(seconds: 20));
      final key = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200 || key['value'] == null) throw 'token service: ${key['error'] ?? res.statusCode}';

      // A permission prompt nobody answers would otherwise leave this pending forever.
      _mic = await navigator.mediaDevices.getUserMedia({
        'audio': {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
        'video': false,
      }).timeout(const Duration(seconds: 15), onTimeout: () => throw 'microphone permission was not granted');
      for (final t in _mic!.getAudioTracks()) {
        t.enabled = false;
      }

      final pc = _pc = await createPeerConnection({'sdpSemantics': 'unified-plan'});
      pc.onTrack = (e) async {
        if (!kIsWeb || e.streams.isEmpty) return;
        _speaker ??= RTCVideoRenderer();
        await _speaker!.initialize();
        _speaker!.srcObject = e.streams.first;
      };
      pc.onConnectionState = (s) {
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          _fail('Voice connection dropped');
        }
      };
      for (final t in _mic!.getAudioTracks()) {
        await pc.addTrack(t, _mic!);
      }

      _open = Completer<void>();
      final dc = _dc = await pc.createDataChannel('oai-events', RTCDataChannelInit()..ordered = true);
      dc.onDataChannelState = (s) {
        if (s == RTCDataChannelState.RTCDataChannelOpen && !(_open?.isCompleted ?? true)) _open!.complete();
      };
      dc.onMessage = (m) => _onEvent(jsonDecode(m.text) as Map<String, dynamic>);

      final offer = await pc.createOffer({'offerToReceiveAudio': true});
      await pc.setLocalDescription(offer);
      final answer = await http
          .post(Uri.parse(key['calls_url'] as String),
              headers: {'Authorization': 'Bearer ${key['value']}', 'Content-Type': 'application/sdp'}, body: offer.sdp)
          .timeout(const Duration(seconds: 30));
      if (answer.statusCode >= 300) throw 'Azure refused the call (${answer.statusCode}): ${answer.body}';
      await pc.setRemoteDescription(RTCSessionDescription(answer.body, 'answer'));

      await _open!.future.timeout(const Duration(seconds: 20));
      _send({'type': 'session.update', 'session': _session});
      state.value = RealtimeState.ready;
    } catch (e) {
      _fail('$e');
      rethrow;
    }
  }

  /// Sends new context, e.g. after a payment changes what is due.
  void updateSession(Map<String, dynamic> session) {
    if (jsonEncode(session) == jsonEncode(_session)) return;
    _session = session;
    if (isUsable) _send({'type': 'session.update', 'session': session});
  }

  /// Unmutes the mic. The model's voice activity detection decides when a turn ends.
  void listen() {
    if (!isUsable) return;
    for (final t in _mic?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = true;
    }
    state.value = RealtimeState.listening;
  }

  void mute() {
    for (final t in _mic?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = false;
    }
    if (state.value == RealtimeState.listening) state.value = RealtimeState.ready;
  }

  Future<void> close() async {
    state.value = RealtimeState.closed;
    await _dc?.close();
    await _pc?.close();
    for (final t in _mic?.getTracks() ?? const <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _mic?.dispose();
    _speaker?.srcObject = null;
    await _speaker?.dispose();
    _dc = null;
    _pc = null;
    _mic = null;
    _speaker = null;
  }

  void _fail(String message) {
    if (state.value == RealtimeState.closed) return;
    state.value = RealtimeState.failed;
    onError?.call(message);
  }

  void _send(Map<String, dynamic> event) => _dc?.send(RTCDataChannelMessage(jsonEncode(event)));

  Future<void> _onEvent(Map<String, dynamic> ev) async {
    switch (ev['type']) {
      case 'error':
        onError?.call((ev['error'] as Map?)?['message']?.toString() ?? 'Realtime error');
      case 'conversation.item.input_audio_transcription.completed':
        final text = (ev['transcript'] as String? ?? '').trim();
        if (text.isNotEmpty) onUserSaid?.call(text);
      case 'response.output_audio_transcript.delta' || 'response.output_text.delta':
        _reply += ev['delta'] as String? ?? '';
        onAssistantText?.call(_reply, false);
      case 'response.function_call_arguments.done':
        _pendingCalls.add(ev);
      case 'response.done':
        if (_reply.isNotEmpty) onAssistantText?.call(_reply, true);
        _reply = '';
        if (_pendingCalls.isEmpty) return;
        final calls = List.of(_pendingCalls);
        _pendingCalls.clear();
        for (final call in calls) {
          Map<String, dynamic> args;
          try {
            args = jsonDecode(call['arguments'] as String? ?? '{}') as Map<String, dynamic>;
          } catch (_) {
            args = {};
          }
          final output = await (onToolCall?.call(call['name'] as String, args) ?? Future.value({'error': 'no handler'}));
          _send({
            'type': 'conversation.item.create',
            'item': {'type': 'function_call_output', 'call_id': call['call_id'], 'output': jsonEncode(output)},
          });
        }
        _send({'type': 'response.create'});
    }
  }
}
