import 'package:flutter/material.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context).loadingLabel;
    return Scaffold(
      body: Center(
        child: Semantics(
          label: label,
          liveRegion: true,
          child: const CircularProgressIndicator(),
        ),
      ),
    );
  }
}
