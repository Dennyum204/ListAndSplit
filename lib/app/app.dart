import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/app/router/app_router.dart';
import 'package:list_and_split/core/theme/app_theme.dart';
import 'package:list_and_split/features/account/presentation/account_session_lifecycle.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class ListAndSplitApp extends ConsumerWidget {
  const ListAndSplitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
      builder: (context, child) => AccountSessionLifecycle(
        child: child ?? const SizedBox.shrink(),
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
