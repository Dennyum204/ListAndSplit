import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/supabase/supabase_client_provider.dart';
import 'package:list_and_split/features/auth/presentation/auth_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/settings/presentation/language_preference_controller.dart';
import '../data/native_push_platform.dart';
import '../data/supabase_push_repository.dart';
import '../domain/push_repository.dart';
import 'push_controller.dart';

final pushPlatformProvider = Provider<PushPlatform>((ref) {
  final platform = NativePushPlatform();
  ref.onDispose(() => unawaited(platform.dispose()));
  return platform;
});
final pushRepositoryProvider = Provider<PushRepository>(
    (ref) => SupabasePushRepository(ref.watch(supabaseClientProvider)));
final pushDestinationProvider = StateProvider<PushDestination?>((ref) => null);
final pushControllerProvider =
    StateNotifierProvider<PushController, PushState>((ref) {
  final controller = PushController(
      ref.watch(pushPlatformProvider), ref.watch(pushRepositoryProvider),
      onDestination: (destination) {
    ref.read(pushDestinationProvider.notifier).state = destination;
  });
  var disposed = false;
  ref.onDispose(() => disposed = true);
  void sync() {
    if (disposed) return;
    final session = ref.read(authSessionProvider);
    if (!session.hasValue) return;
    final user = session.valueOrNull?.user;
    final profile = ref.read(ownProfileProvider);
    if (user != null && !profile.hasValue && !profile.hasError) return;
    final id = user?.isEmailVerified == true &&
            profile.valueOrNull?.isOnboardingComplete == true
        ? user!.id
        : null;
    unawaited(controller.setAccount(
        id,
        ref.read(languagePreferenceControllerProvider).locale?.languageCode ??
            ''));
  }

  ref.listen(authSessionProvider, (_, __) => sync());
  ref.listen(ownProfileProvider, (_, __) => sync());
  ref.listen(languagePreferenceControllerProvider, (_, __) => sync());
  scheduleMicrotask(sync);
  return controller;
});
