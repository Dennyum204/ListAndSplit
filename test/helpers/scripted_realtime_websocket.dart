import 'dart:async';
import 'dart:convert';

import 'package:list_and_split/core/realtime/account_realtime_gateway.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class ScriptedRealtimeConnector {
  final List<ScriptedRealtimeWebSocketChannel> channels = [];
  final List<Duration> connectTimeouts = [];

  WebSocketChannel connect(
    String url, {
    required Map<String, dynamic> headers,
    required Duration connectTimeout,
  }) {
    connectTimeouts.add(connectTimeout);
    final channel = ScriptedRealtimeWebSocketChannel(
      url: url,
      headers: Map.unmodifiable(headers),
      connectTimeout: connectTimeout,
    );
    channels.add(channel);
    return channel;
  }
}

class ScriptedRealtimeWebSocketChannel implements WebSocketChannel {
  ScriptedRealtimeWebSocketChannel({
    required this.url,
    required this.headers,
    required this.connectTimeout,
  })  : _streamController = StreamController<dynamic>(),
        _rawReadyCompleter = Completer<void>(),
        _boundedReadyCompleter = Completer<void>() {
    _sink = _ScriptedRealtimeWebSocketSink(
      _streamController,
      _handleOutboundMessage,
    );
  }

  final String url;
  final Map<String, dynamic> headers;
  final Duration connectTimeout;
  final StreamController<dynamic> _streamController;
  final Completer<void> _rawReadyCompleter;
  final Completer<void> _boundedReadyCompleter;
  late final _ScriptedRealtimeWebSocketSink _sink;

  int joinRequests = 0;
  int leaveRequests = 0;
  String? joinedTopic;
  bool deadlineFired = false;

  bool get rawHandshakeCompleted => _rawReadyCompleter.isCompleted;

  void completeHandshake() {
    if (!_rawReadyCompleter.isCompleted) {
      _rawReadyCompleter.complete();
    }
    if (!_boundedReadyCompleter.isCompleted) {
      _boundedReadyCompleter.complete();
    }
  }

  void fireHandshakeDeadline() {
    if (_boundedReadyCompleter.isCompleted) return;
    if (_rawReadyCompleter.isCompleted) {
      throw StateError('The raw handshake already completed.');
    }
    deadlineFired = true;
    _boundedReadyCompleter.completeError(
      TimeoutException(
        'Realtime WebSocket handshake deadline elapsed.',
        connectTimeout,
      ),
    );
  }

  Future<void> closeFromNetwork() async {
    if (!_streamController.isClosed) {
      await _streamController.close();
    }
  }

  void emitAccountInvalidation(String authenticatedProfileId) {
    final topic = 'realtime:${accountRealtimeTopic(authenticatedProfileId)}';
    if (joinedTopic != topic || _streamController.isClosed) {
      throw StateError('The requested private account topic is not joined.');
    }
    _emit({
      'topic': topic,
      'event': 'broadcast',
      'payload': {
        'event': accountInvalidationEvent,
        'payload': accountInvalidationPayload,
        'type': 'broadcast',
      },
      'ref': null,
    });
  }

  void _handleOutboundMessage(dynamic value) {
    if (value is! String) return;
    final decoded = jsonDecode(value);
    if (decoded is! Map) return;
    final message = Map<String, dynamic>.from(decoded);
    final event = message['event'];
    if (event != 'phx_join' && event != 'phx_leave') return;
    final topic = message['topic'];
    final ref = message['ref'];
    if (topic is! String || ref is! String) return;

    if (event == 'phx_join') {
      joinRequests += 1;
      joinedTopic = topic;
    } else {
      leaveRequests += 1;
    }

    scheduleMicrotask(() {
      if (_streamController.isClosed) return;
      _emit({
        'topic': topic,
        'event': 'phx_reply',
        'payload': {'status': 'ok', 'response': <String, dynamic>{}},
        'ref': ref,
      });
    });
  }

  void _emit(Map<String, dynamic> message) {
    if (!_streamController.isClosed) {
      _streamController.add(jsonEncode(message));
    }
  }

  @override
  Future<void> get ready => _boundedReadyCompleter.future;

  @override
  Stream<dynamic> get stream => _streamController.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ScriptedRealtimeWebSocketSink implements WebSocketSink {
  _ScriptedRealtimeWebSocketSink(
    this._streamController,
    this._onAdd,
  );

  final StreamController<dynamic> _streamController;
  final void Function(dynamic value) _onAdd;
  final Completer<void> _doneCompleter = Completer<void>();

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  void add(dynamic data) => _onAdd(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final value in stream) {
      add(value);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!_streamController.isClosed) {
      await _streamController.close();
    }
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }
}
