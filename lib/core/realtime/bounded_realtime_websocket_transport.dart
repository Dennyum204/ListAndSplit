import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Maximum time allowed for a mobile Realtime WebSocket handshake.
///
/// A bounded handshake is required because the pinned Realtime client keeps a
/// non-null connection while awaiting [WebSocketChannel.ready]. Letting the
/// ready future fail releases that attempt so the client's retry cycle can
/// establish a fresh connection.
const realtimeWebSocketConnectTimeout = Duration(seconds: 15);

typedef RealtimeIoWebSocketConnector = WebSocketChannel Function(
  String url, {
  required Map<String, dynamic> headers,
  required Duration connectTimeout,
});

/// Creates Realtime WebSockets with a bounded, injectable IO handshake.
class BoundedRealtimeWebSocketTransport {
  const BoundedRealtimeWebSocketTransport({
    this.connectTimeout = realtimeWebSocketConnectTimeout,
    RealtimeIoWebSocketConnector connector = _connectIoWebSocket,
  }) : _connector = connector;

  final Duration connectTimeout;
  final RealtimeIoWebSocketConnector _connector;

  WebSocketChannel connect(String url, Map<String, String> headers) {
    return _connector(
      url,
      headers: headers,
      connectTimeout: connectTimeout,
    );
  }
}

WebSocketChannel _connectIoWebSocket(
  String url, {
  required Map<String, dynamic> headers,
  required Duration connectTimeout,
}) {
  return IOWebSocketChannel.connect(
    url,
    headers: headers,
    connectTimeout: connectTimeout,
  );
}
