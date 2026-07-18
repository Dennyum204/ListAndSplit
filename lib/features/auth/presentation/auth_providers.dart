import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/features/auth/data/password_recovery_marker.dart';
import 'package:list_and_split/core/supabase/supabase_client_provider.dart';
import 'package:list_and_split/features/auth/data/supabase_auth_repository.dart';
import 'package:list_and_split/features/auth/domain/auth_repository.dart';
import 'package:list_and_split/features/auth/domain/auth_session.dart';

final passwordRecoveryMarkerProvider = Provider<PasswordRecoveryMarker>(
  (ref) => SharedPreferencesPasswordRecoveryMarker(),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(passwordRecoveryMarkerProvider),
  ),
);

final authSessionProvider = StreamProvider<AuthSessionState>(
  (ref) => ref.watch(authRepositoryProvider).observeSession(),
);

final pendingVerificationEmailProvider = StateProvider<String?>((ref) => null);

final completedPasswordRecoveryAttemptProvider =
    StateProvider<int?>((ref) => null);
