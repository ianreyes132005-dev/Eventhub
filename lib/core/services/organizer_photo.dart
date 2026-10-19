import 'dart:typed_data';

import 'package:image/image.dart' as image;

class OrganizerPhoto {
  OrganizerPhoto._();

  static Uint8List resizeToAvatar(Uint8List bytes) {
    final decoded = image.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('The selected file is not a valid image.');
    }

    final oriented = image.bakeOrientation(decoded);
    const maxDimension = 512;
    final resized = oriented.width > maxDimension ||
            oriented.height > maxDimension
        ? image.copyResize(
            oriented,
            width: oriented.width >= oriented.height ? maxDimension : null,
            height: oriented.height > oriented.width ? maxDimension : null,
          )
        : oriented;
    return Uint8List.fromList(image.encodeJpg(resized, quality: 82));
  }
}
