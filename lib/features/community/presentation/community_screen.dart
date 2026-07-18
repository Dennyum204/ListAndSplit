import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/features/community/domain/community_profile.dart';
import 'package:list_and_split/features/community/presentation/community_search_controller.dart';
import 'package:list_and_split/features/community/presentation/community_ui.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  final _username = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(communitySearchControllerProvider);
    return FormPageFrame(
      title: localizations.communityTitle,
      description: localizations.communityDescription,
      leading: IconButton(
        onPressed: () => context.go(AppRoutes.foundation),
        icon: const Icon(Icons.arrow_back_rounded),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              key: const Key('manageBlockedUsersButton'),
              onPressed: state.isBusy
                  ? null
                  : () => context.go(AppRoutes.blockedUsers),
              icon: const Icon(Icons.block_rounded),
              label: Text(localizations.manageBlockedUsersButton),
            ),
          ),
          const SizedBox(height: 8),
          FormMessageBanner(
            message: state.message == null
                ? null
                : communitySearchMessageText(
                    localizations,
                    state.message!,
                  ),
          ),
          TextField(
            key: const Key('communityUsername'),
            controller: _username,
            enabled: !state.isBusy,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            textInputAction: TextInputAction.search,
            onChanged: (_) => ref
                .read(communitySearchControllerProvider.notifier)
                .clearResultForEditedQuery(),
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: localizations.usernameLabel,
              helperText: localizations.communityUsernameHelper,
              prefixIcon: const Icon(Icons.person_search_rounded),
              errorText: state.usernameError == null
                  ? null
                  : communityUsernameValidationText(
                      localizations,
                      state.usernameError!,
                    ),
            ),
          ),
          const SizedBox(height: 20),
          SubmissionButton(
            label: localizations.communitySearchButton,
            isSubmitting: state.isSearching,
            onPressed: state.isBusy ? null : _search,
          ),
          if (state.result != null) ...[
            const SizedBox(height: 24),
            _DiscoveryResultCard(
              profile: state.result!,
              isBlocking: state.isBlocking,
              onBlock: _confirmBlock,
            ),
          ],
        ],
      ),
    );
  }

  void _search() {
    ref.read(communitySearchControllerProvider.notifier).search(_username.text);
  }

  Future<void> _confirmBlock() async {
    final profile = ref.read(communitySearchControllerProvider).result;
    if (profile == null) return;
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.communityBlockDialogTitle(profile.username)),
        content: Text(localizations.communityBlockDialogDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(localizations.cancelButton),
          ),
          FilledButton(
            key: const Key('confirmBlockButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(localizations.communityBlockButton),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(communitySearchControllerProvider.notifier).blockResult();
    }
  }
}

class _DiscoveryResultCard extends StatelessWidget {
  const _DiscoveryResultCard({
    required this.profile,
    required this.isBlocking,
    required this.onBlock,
  });

  final DiscoveredProfile profile;
  final bool isBlocking;
  final VoidCallback onBlock;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Card(
      key: const Key('communitySearchResult'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              profile.displayName,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '@${profile.username}',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              key: const Key('blockSearchResultButton'),
              onPressed: isBlocking ? null : onBlock,
              icon: isBlocking
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.block_rounded),
              label: Text(localizations.communityBlockButton),
            ),
          ],
        ),
      ),
    );
  }
}
