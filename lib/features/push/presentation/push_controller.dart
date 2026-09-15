import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/push_repository.dart';

class PushState {
  const PushState(
      {this.available = false,
      this.permission = false,
      this.enabled = false,
      this.busy = false,
      this.failed = false});
  final bool available, permission, enabled, busy, failed;
}

class PushController extends StateNotifier<PushState> {
  PushController(this._platform, this._repository,
      {required this.onDestination})
      : super(const PushState()) {
    _events = _platform.events.listen((tap) {
      if (tap == null) {
        if (!state.busy) {
          unawaited(refresh());
        } else {
          _refreshPending = true;
        }
      } else {
        unawaited(_route(tap));
      }
    });
  }
  final PushPlatform _platform;
  final PushRepository _repository;
  final void Function(PushDestination) onDestination;
  late final StreamSubscription<PushTap?> _events;
  String? _account;
  String _language = '';
  PushBinding? _binding;
  int _generation = 0;
  bool _initialized = false;
  bool _confirmedEnabled = false;
  bool _refreshPending = false;
  final _handledTaps = <String>{};
  PushTap? _pendingTap;

  Future<void> setAccount(String? account, String language) async {
    if (_initialized && account == _account && language == _language) return;
    _initialized = true;
    if (account != _account) {
      _handledTaps.clear();
      _pendingTap = null;
      _binding = null;
      _confirmedEnabled = false;
      state = const PushState();
    }
    _account = account;
    _language = language;
    await _synchronize();
  }

  Future<void> refresh() async {
    if (!state.busy) await _synchronize();
  }

  Future<void> _synchronize() async {
    final generation = ++_generation;
    state = PushState(
        available: state.available,
        permission: state.permission,
        enabled: state.enabled,
        busy: true);
    try {
      final binding = await _platform.bind(_account, _language);
      if (!mounted || generation != _generation) return;
      if (_account == null || binding == null) {
        state = const PushState();
        return;
      }
      await _apply(binding, generation);
      if (mounted && generation == _generation && binding.available) {
        final tap = await _platform.takeTap() ?? _pendingTap;
        if (tap != null) await _route(tap);
      }
    } catch (_) {
      if (mounted && generation == _generation) _fail();
    } finally {
      _runPending(generation);
    }
  }

  Future<void> _apply(PushBinding binding, int generation) async {
    _binding = binding;
    final account = _account;
    if (account == null) return;
    final enabled = binding.available &&
        binding.permission &&
        binding.enabled &&
        binding.token != null;
    if (enabled) {
      await _repository.register(account, binding);
      if (!mounted || generation != _generation) return;
      await _platform.confirm(binding.binding);
      if (!mounted || generation != _generation) return;
      _confirmedEnabled = true;
    } else if (binding.available) {
      _confirmedEnabled = false;
      await _repository.unregister(account, binding);
    }
    if (mounted && generation == _generation) {
      state = PushState(
          available: binding.available,
          permission: binding.permission,
          enabled: enabled);
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (state.busy || _account == null || !state.available) return;
    final generation = ++_generation;
    state = PushState(
        available: true,
        enabled: state.enabled,
        permission: state.permission,
        busy: true);
    try {
      final binding =
          enabled ? await _platform.enable() : await _platform.disable();
      if (mounted && generation == _generation) {
        await _apply(binding, generation);
      }
    } catch (_) {
      if (mounted && generation == _generation) _fail();
    } finally {
      _runPending(generation);
    }
  }

  void _runPending(int generation) {
    if (mounted && generation == _generation && _refreshPending) {
      _refreshPending = false;
      unawaited(refresh());
    }
  }

  void _fail() => state = PushState(
      available: _binding?.available ?? state.available,
      enabled: _confirmedEnabled,
      permission: _binding?.permission ?? state.permission,
      failed: true);
  Future<void> stopBeforeSignOut() async {
    final previous = _binding;
    final account = _account;
    ++_generation;
    _initialized = false;
    _binding = null;
    _confirmedEnabled = false;
    _handledTaps.clear();
    _pendingTap = null;
    await _platform.bind(null,
        _language); // Stops local alerts before Auth changes, also offline.
    if (mounted) state = const PushState();
    if (previous != null && account != null && previous.available) {
      unawaited(
          _repository.unregister(account, previous).catchError((Object _) {}));
    }
  }

  Future<void> _route(PushTap tap) async {
    final generation = _generation;
    if (tap.account != _account ||
        tap.binding != _binding?.binding ||
        _handledTaps.contains(tap.delivery)) {
      return;
    }
    _handledTaps.add(tap.delivery);
    if (_handledTaps.length > 128) _handledTaps.remove(_handledTaps.first);
    try {
      final destination = await _repository.resolve(tap);
      if (mounted && generation == _generation) _pendingTap = null;
      if (mounted &&
          generation == _generation &&
          tap.account == _account &&
          destination != null) {
        onDestination(destination);
      }
    } catch (_) {
      // Keep a visible recoverable status. Never trust a payload as access proof.
      if (mounted && generation == _generation) {
        _handledTaps.remove(tap.delivery);
        _pendingTap = tap;
        _fail();
      }
    }
  }

  Future<void> openSettings() => _platform.openSettings();
  Future<void> visibleChat(String? list) => _platform.visibleChat(list);
  @override
  void dispose() {
    ++_generation;
    unawaited(_events.cancel());
    super.dispose();
  }
}
