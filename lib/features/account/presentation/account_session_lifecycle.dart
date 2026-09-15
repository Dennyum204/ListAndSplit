import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/app/reconciliation/account_reconciliation_providers.dart';
import 'package:list_and_split/app/session_state_reset.dart';
import 'package:list_and_split/core/config/configuration_provider.dart';
import 'package:list_and_split/core/supabase/supabase_client_provider.dart';
import 'package:list_and_split/features/account/domain/account_deletion_repository.dart';
import 'package:list_and_split/features/account/presentation/account_deletion_providers.dart';
import 'package:list_and_split/features/auth/presentation/auth_providers.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/app_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/features/push/presentation/push_providers.dart';

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
  GoRouter? _pushRouter;

  void _syncPushRoute() {
    if (!mounted || _pushRouter == null) return;
    final match = RegExp(r'^/lists/([0-9a-f-]{36})/chat$')
        .firstMatch(_pushRouter!.routeInformationProvider.value.uri.path);
    unawaited(ref
        .read(pushControllerProvider.notifier)
        .visibleChat(match?.group(1))
        .catchError((Object _) {}));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _pushRouter?.routeInformationProvider.removeListener(_syncPushRoute);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _validateSession();
      if (ref.read(supabaseRuntimeReadyProvider)) {
        unawaited(ref.read(pushControllerProvider.notifier).refresh());
        _syncPushRoute();
      }
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
      } else if (ref.read(supabaseRuntimeReadyProvider)) {
        ref.read(accountReconciliationCoordinatorProvider).resume();
      }
    } finally {
      _isValidating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(appConfigurationProvider).isConfigured) {
      ref.watch(authSessionProvider);
      if (ref.watch(supabaseRuntimeReadyProvider)) {
        ref.watch(accountReconciliationCoordinatorProvider);
        ref.watch(pushControllerProvider);
        ref.listen(pushDestinationProvider, (_, destination) {
          if (destination == null) return;
          ref.read(appRouterProvider).go(destination.kind == 'chat'
              ? AppRoutes.listChat(destination.listId!)
              : AppRoutes.notifications);
          ref.read(pushDestinationProvider.notifier).state = null;
        });
        if (_pushRouter == null) {
          _pushRouter = ref.read(appRouterProvider);
          _pushRouter!.routeInformationProvider.addListener(_syncPushRoute);
          WidgetsBinding.instance.addPostFrameCallback((_) => _syncPushRoute());
        }
      }
    }
    return widget.child;
  }
}
