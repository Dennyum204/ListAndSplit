import 'package:shared_preferences/shared_preferences.dart';

abstract interface class PasswordRecoveryMarker {
  Future<bool> read();

  Future<void> write(bool isPending);
}

class SharedPreferencesPasswordRecoveryMarker
    implements PasswordRecoveryMarker {
  static const storageKey = 'auth.password_recovery_pending';

  @override
  Future<bool> read() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(storageKey) ?? false;
  }

  @override
  Future<void> write(bool isPending) async {
    final preferences = await SharedPreferences.getInstance();
    if (!isPending && !preferences.containsKey(storageKey)) return;
    final didPersist = isPending
        ? await preferences.setBool(storageKey, true)
        : await preferences.remove(storageKey);
    if (!didPersist) {
      throw StateError('Could not persist the password-recovery gate.');
    }
  }
}

enum PasswordRecoverySessionEvent {
  initialSession,
  passwordRecovery,
  signedIn,
  signedOut,
  tokenRefreshed,
  userUpdated,
  other,
}

class PasswordRecoveryLifecycle {
  PasswordRecoveryLifecycle(this._marker);

  final PasswordRecoveryMarker _marker;
  Future<void>? _restoreOperation;
  bool _isPending = false;
  int _attempt = 0;

  bool get isPending => _isPending;
  int get attempt => _attempt;

  Future<void> handle(PasswordRecoverySessionEvent event) async {
    await _restore();
    switch (event) {
      case PasswordRecoverySessionEvent.passwordRecovery:
        await _marker.write(true);
        _isPending = true;
        _attempt += 1;
        break;
      case PasswordRecoverySessionEvent.signedIn:
      case PasswordRecoverySessionEvent.signedOut:
        await _clear(resetAttempt: true);
        break;
      case PasswordRecoverySessionEvent.initialSession:
      case PasswordRecoverySessionEvent.tokenRefreshed:
      case PasswordRecoverySessionEvent.userUpdated:
      case PasswordRecoverySessionEvent.other:
        break;
    }
  }

  Future<void> complete() async {
    await _restore();
    await _clear(resetAttempt: false);
  }

  Future<void> _restore() => _restoreOperation ??= _restoreFromStorage();

  Future<void> _restoreFromStorage() async {
    _isPending = await _marker.read();
    if (_isPending && _attempt == 0) _attempt = 1;
  }

  Future<void> _clear({required bool resetAttempt}) async {
    await _marker.write(false);
    _isPending = false;
    if (resetAttempt) _attempt = 0;
  }
}
