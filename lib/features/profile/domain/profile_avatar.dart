import 'dart:typed_data';

class AvatarTarget {
  const AvatarTarget.profile(this.id) : kind = 'profile';
  const AvatarTarget.chat(this.id) : kind = 'chat';
  const AvatarTarget.split(this.id) : kind = 'split';
  final String kind;
  final String id;
  @override
  bool operator ==(Object other) =>
      other is AvatarTarget && other.kind == kind && other.id == id;
  @override
  int get hashCode => Object.hash(kind, id);
}

enum AvatarFailureKind { retryable, stale, busy, invalidImage, unavailable }

class AvatarFailure implements Exception {
  const AvatarFailure([this.kind = AvatarFailureKind.retryable]);
  final AvatarFailureKind kind;
}

class ProfileAvatarMetadata {
  const ProfileAvatarMetadata({required this.version, required this.hasImage});
  factory ProfileAvatarMetadata.fromJson(Object? value) {
    if (value is! Map ||
        value.length != 2 ||
        value['version'] is! int ||
        (value['version'] as int) < 0 ||
        value['has_image'] is! bool) {
      throw const AvatarFailure();
    }
    return ProfileAvatarMetadata(
        version: value['version'] as int, hasImage: value['has_image'] as bool);
  }
  final int version;
  final bool hasImage;
}

abstract interface class ProfileAvatarRepository {
  Future<ProfileAvatarMetadata> metadata();
  Future<Uint8List?> read(AvatarTarget target);
  Future<ProfileAvatarMetadata> replace(
      Uint8List png, int version, String requestId, String expectedUser);
  Future<ProfileAvatarMetadata> remove(
      int version, String requestId, String expectedUser);
}

abstract interface class AvatarGallery {
  Future<Uint8List?> selectThumbnail();
}
