import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/app/session_state_reset.dart';
import 'package:list_and_split/core/config/configuration_provider.dart';
import 'package:list_and_split/features/account/domain/account_deletion_repository.dart';
import 'package:list_and_split/features/account/presentation/account_deletion_providers.dart';
import 'package:list_and_split/features/auth/presentation/auth_providers.dart';

class AccountSessionLifecycle extends ConsumerStatefulWidget {
  const AccountSessionLifecycle({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AccountSessionLifecycle> createState() =>
      _AccountSessionLifecycleState();
}

class _AccountSessionLifecycleState
    extends ConsumerState<AccountSessionLifecycle> with WidgetsBindingObserver {
  var _isValidating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _validateSession();
    }
  }

  Future<void> _validateSession() async {
    if (_isValidating ||
        !ref.read(appConfigurationProvider).isConfigured ||
        ref.read(authSessionProvider).valueOrNull?.user?.isEmailVerified !=
            true) {
      return;
    }
    _isValidating = true;
    try {
      final repository = ref.read(accountDeletionRepositoryProvider);
      final result = await repository.validateCurrentAccount();
      if (result == AuthoritativeAccountState.missing ||
          result == AuthoritativeAccountState.invalidSession) {
        await repository.clearLocalSession();
        ref.read(resetSessionStateProvider)();
      }
    } finally {
      _isValidating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(appConfigurationProvider).isConfigured) {
      ref.watch(authSessionProvider);
    }
    return widget.child;
  }
}
