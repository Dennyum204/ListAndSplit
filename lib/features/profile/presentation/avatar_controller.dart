import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/features/lists/domain/creation_request_id.dart';
import 'package:list_and_split/features/profile/domain/profile_avatar.dart';

class AvatarEditorState {
  const AvatarEditorState(
      {this.busy = false, this.error, this.changed = false});
  final bool busy;
  final AvatarFailureKind? error;
  final bool changed;
}

class AvatarController extends StateNotifier<AvatarEditorState> {
  AvatarController(this.repository, this.gallery, this.userId, this.onRefresh)
      : super(const AvatarEditorState());
  final ProfileAvatarRepository repository;
  final AvatarGallery gallery;
  final String? userId;
  final void Function() onRefresh;
  Future<void> submit({required bool remove}) async {
    if (state.busy || userId == null) return;
    state = const AvatarEditorState(busy: true);
    try {
      final current = await repository.metadata();
      if (!mounted) return;
      final bytes = remove ? null : await gallery.selectThumbnail();
      if (!mounted) return;
      if (!remove && bytes == null) {
        state = const AvatarEditorState();
        return;
      }
      final request = secureCreationRequestId();
      if (remove) {
        await repository.remove(current.version, request, userId!);
      } else {
        await repository.replace(bytes!, current.version, request, userId!);
      }
      if (!mounted) return;
      onRefresh();
      state = const AvatarEditorState(changed: true);
    } catch (error) {
      if (!mounted) return;
      onRefresh();
      state = AvatarEditorState(
          error: error is AvatarFailure
              ? error.kind
              : AvatarFailureKind.retryable);
    }
  }
}
