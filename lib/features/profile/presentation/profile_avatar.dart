import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/presentation/design_widgets.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';
import 'package:list_and_split/core/supabase/supabase_client_provider.dart';
import 'package:list_and_split/features/profile/data/avatar_gallery.dart';
import 'package:list_and_split/features/profile/data/supabase_profile_avatar_repository.dart';
import 'package:list_and_split/features/profile/domain/profile_avatar.dart';
import 'package:list_and_split/features/profile/presentation/avatar_controller.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';
export 'package:list_and_split/features/profile/domain/profile_avatar.dart'
    show AvatarTarget;

final profileAvatarRepositoryProvider = Provider<ProfileAvatarRepository>(
    (ref) =>
        SupabaseProfileAvatarRepository(ref.watch(supabaseClientProvider)));
final avatarGalleryProvider =
    Provider<AvatarGallery>((ref) => DeviceAvatarGallery());
final ownAvatarMetadataProvider =
    FutureProvider.autoDispose<ProfileAvatarMetadata?>((ref) async {
  if (!ref.watch(supabaseRuntimeReadyProvider) ||
      ref.watch(verifiedUserIdProvider) == null) {
    return null;
  }
  registerForReconciliation(ref, () async {
    ref.invalidateSelf();
  });
  return ref.watch(profileAvatarRepositoryProvider).metadata();
});
final avatarBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, AvatarTarget>((ref, target) async {
  if (!ref.watch(supabaseRuntimeReadyProvider) ||
      ref.watch(verifiedUserIdProvider) == null) {
    return null;
  }
  registerForReconciliation(ref, () async {
    ref.invalidateSelf();
  });
  Uint8List? bytes;
  ref.onDispose(() {
    if (bytes != null) MemoryImage(bytes).evict();
  });
  bytes = await ref.watch(profileAvatarRepositoryProvider).read(target);
  return bytes;
});
final avatarControllerProvider =
    StateNotifierProvider.autoDispose<AvatarController, AvatarEditorState>(
        (ref) => AvatarController(
                ref.watch(profileAvatarRepositoryProvider),
                ref.watch(avatarGalleryProvider),
                ref.watch(verifiedUserIdProvider), () {
              ref.invalidate(avatarBytesProvider);
              ref.invalidate(ownAvatarMetadataProvider);
            }));

class ProfileAvatar extends ConsumerWidget {
  const ProfileAvatar(
      {required this.label,
      required this.target,
      this.size = 40,
      this.backgroundColor,
      super.key});
  final String label;
  final AvatarTarget? target;
  final double size;
  final Color? backgroundColor;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result =
        target == null ? null : ref.watch(avatarBytesProvider(target!));
    final bytes = result != null && !result.isLoading && !result.hasError
        ? result.valueOrNull
        : null;
    final fallback = IdentityBadge(
        label: label, size: size, backgroundColor: backgroundColor);
    if (bytes == null) return fallback;
    return ExcludeSemantics(
        child: ClipOval(
            child: Image.memory(bytes,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: false,
                // Keep initials visible until decoding finishes, rather than
                // exposing an empty frame. Revalidation/access failures still
                // discard the photo; never carry bytes into another identity.
                frameBuilder: (_, child, frame, synchronous) =>
                    synchronous || frame != null ? child : fallback,
                errorBuilder: (_, __, ___) => fallback)));
  }
}

class AvatarEditorActions extends ConsumerWidget {
  const AvatarEditorActions({super.key, this.disabled = false});
  final bool disabled;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(supabaseRuntimeReadyProvider)) {
      return const SizedBox.shrink();
    }
    final state = ref.watch(avatarControllerProvider);
    final metadata = ref.watch(ownAvatarMetadataProvider);
    final current =
        metadata.isReloading || metadata.hasError ? null : metadata.valueOrNull;
    final l10n = AppLocalizations.of(context);
    final message = state.error == null
        ? (state.changed ? l10n.avatarSaved : null)
        : switch (state.error!) {
            AvatarFailureKind.busy => l10n.avatarBusy,
            AvatarFailureKind.stale => l10n.avatarStale,
            AvatarFailureKind.invalidImage => l10n.avatarInvalidImage,
            _ => l10n.avatarFailed,
          };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 12, children: [
        OutlinedButton.icon(
            key: const Key('changeAvatarButton'),
            onPressed: state.busy || disabled
                ? null
                : () => ref
                    .read(avatarControllerProvider.notifier)
                    .submit(remove: false),
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(current == null
                ? l10n.avatarChoose
                : current.hasImage
                    ? l10n.avatarUpdate
                    : l10n.avatarAdd)),
        if (current?.hasImage == true)
          TextButton.icon(
              key: const Key('removeAvatarButton'),
              onPressed: state.busy || disabled
                  ? null
                  : () => ref
                      .read(avatarControllerProvider.notifier)
                      .submit(remove: true),
              icon: const Icon(Icons.person_remove_outlined),
              label: Text(l10n.avatarRemove)),
      ]),
      if (state.busy)
        Semantics(
            liveRegion: true,
            label: l10n.avatarSaving,
            child: const LinearProgressIndicator()),
      if (message != null) Semantics(liveRegion: true, child: Text(message)),
    ]);
  }
}
