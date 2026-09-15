import 'dart:async';
import 'package:flutter/services.dart';
import '../domain/push_repository.dart';

class NativePushPlatform implements PushPlatform {
  NativePushPlatform({MethodChannel? channel})
      : _channel =
            channel ?? const MethodChannel('com.ferbatech.listandsplit/push') {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'token') _events.add(null);
      if (call.method == 'tap') {
        final tap = _tap(call.arguments);
        if (tap != null) _events.add(tap);
      }
    });
  }
  final MethodChannel _channel;
  final _events = StreamController<PushTap?>.broadcast();
  @override
  Stream<PushTap?> get events => _events.stream;
  static final _uuid =
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
  PushTap? _tap(Object? value) {
    if (value is! Map) return null;
    for (final name in ['delivery', 'binding', 'account']) {
      if (value[name] is! String || !_uuid.hasMatch(value[name] as String)) {
        return null;
      }
    }
    return PushTap(value['delivery'] as String, value['binding'] as String,
        value['account'] as String);
  }

  PushBinding _binding(Map value) => PushBinding(
      available: value['available'] == true,
      permission: value['permission'] == true,
      enabled: value['enabled'] == true,
      installation: value['installation'] as String? ?? '',
      binding: value['binding'] as String? ?? '',
      token: value['token'] as String?);
  @override
  Future<PushBinding?> bind(String? account, String language) async {
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
          'bind', {'account': account, 'language': language});
      return value == null ? null : _binding(value);
    } on MissingPluginException {
      return const PushBinding(
          available: false,
          permission: false,
          enabled: false,
          installation: '',
          binding: '');
    }
  }

  @override
  Future<PushBinding> enable() async =>
      _binding((await _channel.invokeMapMethod<String, Object?>('enable'))!);
  @override
  Future<PushBinding> disable() async =>
      _binding((await _channel.invokeMapMethod<String, Object?>('disable'))!);
  @override
  Future<void> confirm(String binding) =>
      _channel.invokeMethod('confirm', {'binding': binding});
  @override
  Future<PushTap?> takeTap() async =>
      _tap(await _channel.invokeMethod<Object?>('takeTap'));
  @override
  Future<void> visibleChat(String? list) =>
      _channel.invokeMethod('visibleChat', {'list': list});
  @override
  Future<void> openSettings() => _channel.invokeMethod('settings');
  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _events.close();
  }
}
