import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';
import 'package:list_and_split/core/supabase/supabase_client_provider.dart';
import 'package:list_and_split/features/community/presentation/community_providers.dart';
import 'package:list_and_split/features/community/presentation/friendship_providers.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/templates/data/supabase_public_template_repository.dart';
import 'package:list_and_split/features/templates/domain/public_template_repository.dart';
import 'package:list_and_split/features/templates/presentation/private_template_providers.dart';
import 'package:list_and_split/features/templates/presentation/public_templates_controller.dart';

final publicTemplateRepositoryProvider = Provider<PublicTemplateRepository>(
  (ref) => SupabasePublicTemplateRepository(
    ref.watch(supabaseClientProvider),
  ),
);

class PublicTemplateAccessLossGuard {
  bool _claimed = false;

  bool tryClaim() {
    if (_claimed) return false;
    _claimed = true;
    return true;
  }
}

final publicTemplateAccessLossGuardProvider =
    Provider.autoDispose.family<PublicTemplateAccessLossGuard, String>(
  (ref, profileId) => PublicTemplateAccessLossGuard(),
);

final publicProfileTemplatesControllerProvider =
    StateNotifierProvider.autoDispose.family<PublicProfileTemplatesController,
        PublicProfileTemplatesState, String>(
  (ref, profileId) {
    final userId = ref.watch(verifiedUserIdProvider);
    final controller = PublicProfileTemplatesController(
      ref.watch(publicTemplateRepositoryProvider),
      ref.watch(communityRepositoryProvider),
      profileId,
      hasAuthenticatedUser: userId != null,
      canBlock: userId != null && userId != profileId,
      invalidateCommunity: () {
        ref.read(invalidateCommunitySearchProvider)();
        ref.read(invalidateFriendshipManagementProvider)();
      },
      invalidateNotifications: ref.watch(invalidateNotificationsProvider),
    );
    registerForReconciliation(ref, controller.reconcile);
    if (userId != null) unawaited(controller.load());
    return controller;
  },
);

class PublicTemplateLocation {
  const PublicTemplateLocation({
    required this.profileId,
    required this.templateId,
  });

  final String profileId;
  final String templateId;

  @override
  bool operator ==(Object other) =>
      other is PublicTemplateLocation &&
      other.profileId == profileId &&
      other.templateId == templateId;

  @override
  int get hashCode => Object.hash(profileId, templateId);
}

final publicTemplateDetailControllerProvider = StateNotifierProvider.autoDispose
    .family<PublicTemplateDetailController, PublicTemplateDetailState,
        PublicTemplateLocation>(
  (ref, location) {
    final userId = ref.watch(verifiedUserIdProvider);
    final controller = PublicTemplateDetailController(
      ref.watch(publicTemplateRepositoryProvider),
      ref.watch(communityRepositoryProvider),
      location.profileId,
      location.templateId,
      canBlock: userId != null && userId != location.profileId,
      invalidatePrivateTemplates: ref.watch(invalidatePrivateTemplatesProvider),
      invalidateCommunity: () {
        ref.read(invalidateCommunitySearchProvider)();
        ref.read(invalidateFriendshipManagementProvider)();
      },
      invalidateNotifications: ref.watch(invalidateNotificationsProvider),
    );
    registerForReconciliation(ref, controller.reconcile);
    if (userId != null) unawaited(controller.load());
    return controller;
  },
);
