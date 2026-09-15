import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/presentation/design_widgets.dart';
import 'package:list_and_split/core/supabase/supabase_client_provider.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';
import 'push_providers.dart';

class PushSettingsCard extends ConsumerWidget {
  const PushSettingsCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(supabaseRuntimeReadyProvider)) {
      return const SizedBox.shrink();
    }
    final state = ref.watch(pushControllerProvider);
    final strings = AppLocalizations.of(context);
    final controller = ref.read(pushControllerProvider.notifier);
    return AppSectionCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(strings.pushTitle, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(state.available ? strings.pushExplanation : strings.pushUnavailable),
      SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(strings.pushEnable),
          value: state.enabled,
          onChanged:
              state.busy || !state.available ? null : controller.setEnabled),
      if (state.failed) Text(strings.pushFailed),
      if (state.failed)
        TextButton(
            onPressed: state.busy ? null : controller.refresh,
            child: Text(strings.welcomeRetryButton)),
      if (state.available && !state.permission)
        Text(strings.pushPermissionDenied),
      if (state.available)
        TextButton.icon(
            onPressed: controller.openSettings,
            icon: const Icon(Icons.notifications_outlined),
            label: Text(strings.pushOpenSettings)),
    ]));
  }
}
