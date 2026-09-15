import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:list_and_split/features/profile/domain/profile_avatar.dart';

Uint8List createAvatarThumbnail(Uint8List input) {
  if (input.isEmpty || input.length > 5 * 1024 * 1024) {
    throw const AvatarFailure(AvatarFailureKind.invalidImage);
  }
  final decoder = image.findDecoderForData(input);
  final info = decoder?.startDecode(input);
  if (info == null ||
      info.width < 1 ||
      info.height < 1 ||
      info.width * info.height > 16000000 ||
      info.numFrames != 1) {
    throw const AvatarFailure(AvatarFailureKind.invalidImage);
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) {
    throw const AvatarFailure(AvatarFailureKind.invalidImage);
  }
  final resized =
      image.copyResizeCropSquare(image.bakeOrientation(decoded), size: 256);
  // Fresh pixel-only canvas deliberately discards all source metadata.
  final clean = image.Image(width: 256, height: 256, numChannels: 4);
  image.compositeImage(clean, resized);
  return Uint8List.fromList(image.encodePng(clean, level: 6));
}

class DeviceAvatarGallery implements AvatarGallery {
  DeviceAvatarGallery({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;
  @override
  Future<Uint8List?> selectThumbnail() async {
    // Never automatically publish a selection recovered from an old app/session.
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _picker.retrieveLostData();
    }
    final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        requestFullMetadata: false);
    if (file == null) return null;
    if (await file.length() > 5 * 1024 * 1024) {
      throw const AvatarFailure(AvatarFailureKind.invalidImage);
    }
    return compute(createAvatarThumbnail, await file.readAsBytes());
  }
}
