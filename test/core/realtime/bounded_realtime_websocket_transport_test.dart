import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/realtime/bounded_realtime_websocket_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test('forwards the named mobile handshake timeout and headers', () async {
    final connector = _ControllableConnector();
    final transport = BoundedRealtimeWebSocketTransport(
      connector: connector.connect,
    );

    const headers = {'Authorization': 'redacted'};
    final channel = transport.connect('wss://example.invalid/socket', headers);

    expect(channel, same(connector.channels.single));
    expect(connector.urls, ['wss://example.invalid/socket']);
    expect(connector.headers, [headers]);
    expect(connector.timeouts, [realtimeWebSocketConnectTimeout]);
    expect(realtimeWebSocketConnectTimeout, const Duration(seconds: 15));

    await channel.sink.close();
  });

  test('a timed-out handshake is released and a later attempt succeeds',
      () async {
    final connector = _ControllableConnector();
    final transport = BoundedRealtimeWebSocketTransport(
      connector: connector.connect,
    );
    final client = RealtimeClient(
      'wss://example.invalid/realtime/v1',
      transport: transport.connect,
      heartbeatIntervalMs: const Duration(minutes: 1).inMilliseconds,
      reconnectAfterMs: (_) => 0,
    );

    final realtimeChannel = client.channel('test').subscribe();
    await _flushEventQueue();

    expect(connector.channels, hasLength(1));
    final stalledChannel = connector.channels.single;
    expect(stalledChannel.handshakeCompleted, isFalse);

    connector.fireDeadline(0);
    await _flushEventQueue();

    expect(connector.deadlineFired, [isTrue, isFalse]);
    expect(stalledChannel.handshakeCompleted, isFalse);
    expect(connector.channels, hasLength(2));
    final recoveredChannel = connector.channels.last;
    connector.completeHandshake(1);
    await _flushEventQueue();

    expect(client.conn, same(recoveredChannel));
    expect(client.conn, isNot(same(stalledChannel)));
    expect(client.connState, SocketStates.open);
    expect(
      connector.channels.where((channel) => identical(channel, client.conn)),
      hasLength(1),
    );
    expect(
      connector.timeouts,
      everyElement(realtimeWebSocketConnectTimeout),
    );

    await realtimeChannel.unsubscribe(Duration.zero);
    await client.disconnect();
    await stalledChannel.sink.close();
    expect(recoveredChannel.closeCount, 1);
  });
}

Future<void> _flushEventQueue() async {
  for (var i = 0; i < 5; i += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _ControllableConnector {
  final List<String> urls = [];
  final List<Map<String, dynamic>> headers = [];
  final List<Duration> timeouts = [];
  final List<_ControllableWebSocketChannel> channels = [];
  final List<_ControllableHandshake> _handshakes = [];

  List<bool> get deadlineFired =>
      _handshakes.map((handshake) => handshake.deadlineFired).toList();

  WebSocketChannel connect(
    String url, {
    required Map<String, dynamic> headers,
    required Duration connectTimeout,
  }) {
    urls.add(url);
    this.headers.add(Map.unmodifiable(headers));
    timeouts.add(connectTimeout);

    final handshake = _ControllableHandshake(connectTimeout);
    final channel = _ControllableWebSocketChannel(handshake);
    _handshakes.add(handshake);
    channels.add(channel);
    return channel;
  }

  void fireDeadline(int index) {
    _handshakes[index].fireDeadline();
  }

  void completeHandshake(int index) {
    _handshakes[index].complete();
  }
}

class _ControllableWebSocketChannel implements WebSocketChannel {
  _ControllableWebSocketChannel(this._handshake)
      : _streamController = StreamController<dynamic>() {
    _sink = _ControllableWebSocketSink(_streamController);
  }

  final _ControllableHandshake _handshake;
  final StreamController<dynamic> _streamController;
  late final _ControllableWebSocketSink _sink;

  bool get handshakeCompleted => _handshake.handshakeCompleted;
  int get closeCount => _sink.closeCount;

  @override
  Future<void> get ready => _handshake.ready;

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

class _ControllableHandshake {
  _ControllableHandshake(this.timeout);

  final Duration timeout;
  final Completer<void> _rawReadyCompleter = Completer<void>();
  final Completer<void> _boundedReadyCompleter = Completer<void>();
  bool deadlineFired = false;

  Future<void> get ready => _boundedReadyCompleter.future;
  bool get handshakeCompleted => _rawReadyCompleter.isCompleted;

  void fireDeadline() {
    expect(timeout, realtimeWebSocketConnectTimeout);
    expect(_rawReadyCompleter.isCompleted, isFalse);
    deadlineFired = true;
    _boundedReadyCompleter.completeError(
      TimeoutException(
        'Handshake exceeded the configured deadline.',
        timeout,
      ),
    );
  }

  void complete() {
    _rawReadyCompleter.complete();
    _boundedReadyCompleter.complete();
  }
}

class _ControllableWebSocketSink implements WebSocketSink {
  _ControllableWebSocketSink(this._streamController);

  final StreamController<dynamic> _streamController;
  final Completer<void> _doneCompleter = Completer<void>();
  int closeCount = 0;

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  void add(dynamic data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closeCount += 1;
    if (!_streamController.isClosed) {
      unawaited(_streamController.close());
    }
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }
}
