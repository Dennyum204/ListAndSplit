import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/features/profile/domain/profile_repository.dart';
import 'package:list_and_split/features/profile/domain/profile_validation.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';

enum ProfileField { username, displayName }

enum ProfileActionMessage { usernameUnavailable, saved, operationFailed }

class ProfileActionState {
  const ProfileActionState({
    this.isSubmitting = false,
    this.fieldErrors = const {},
    this.message,
  });

  final bool isSubmitting;
  final Map<ProfileField, ProfileValidationIssue> fieldErrors;
  final ProfileActionMessage? message;
}

class ProfileController extends StateNotifier<ProfileActionState> {
  ProfileController(
    this._repository, {
    required void Function() onProfileChanged,
  })  : _onProfileChanged = onProfileChanged,
        super(const ProfileActionState());

  final ProfileRepository _repository;
  final void Function() _onProfileChanged;

  Future<bool> completeOnboarding({
    required String username,
    required String displayName,
  }) async {
    final errors = <ProfileField, ProfileValidationIssue>{};
    final usernameError = ProfileValidation.username(username);
    final displayNameError = ProfileValidation.displayName(displayName);
    if (usernameError != null) errors[ProfileField.username] = usernameError;
    if (displayNameError != null) {
      errors[ProfileField.displayName] = displayNameError;
    }
    if (!_beginIfValid(errors)) return false;

    return _run(() {
      return _repository.completeOnboarding(
        username: ProfileValidation.normalizeUsername(username),
        displayName: ProfileValidation.normalizeDisplayName(displayName),
      );
    });
  }

  Future<bool> updateDisplayName(String displayName) async {
    final error = ProfileValidation.displayName(displayName);
    if (error != null) {
      state = ProfileActionState(
        fieldErrors: {ProfileField.displayName: error},
      );
      return false;
    }
    if (!_beginIfValid(const {})) return false;
    return _run(() {
      return _repository.updateDisplayName(
        displayName: ProfileValidation.normalizeDisplayName(displayName),
      );
    });
  }

  bool _beginIfValid(Map<ProfileField, ProfileValidationIssue> errors) {
    if (state.isSubmitting) return false;
    if (errors.isNotEmpty) {
      state = ProfileActionState(fieldErrors: errors);
      return false;
    }
    state = const ProfileActionState(isSubmitting: true);
    return true;
  }

  Future<bool> _run(Future<Object?> Function() operation) async {
    try {
      await operation();
      state = const ProfileActionState(message: ProfileActionMessage.saved);
      _onProfileChanged();
      return true;
    } on ProfileFailure catch (failure) {
      state = ProfileActionState(
        message: failure.code == ProfileFailureCode.usernameUnavailable
            ? ProfileActionMessage.usernameUnavailable
            : ProfileActionMessage.operationFailed,
      );
      return false;
    } catch (_) {
      state = const ProfileActionState(
        message: ProfileActionMessage.operationFailed,
      );
      return false;
    }
  }
}

final profileControllerProvider =
    StateNotifierProvider.autoDispose<ProfileController, ProfileActionState>(
        (ref) {
  return ProfileController(
    ref.watch(profileRepositoryProvider),
    onProfileChanged: () => ref.invalidate(ownProfileProvider),
  );
});
