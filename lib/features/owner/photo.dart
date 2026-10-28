import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../data/backend.dart';

/// Opens the camera or gallery and returns a compressed photo + thumbnail,
/// or null if the shopkeeper cancelled.
Future<ProductPhoto?> pickProductPhoto(ImageSource source) async {
  final file = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1600, // the picker already shrinks huge camera photos
    maxHeight: 1600,
    imageQuality: 90,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  return compute(compressProductPhoto, bytes);
}

/// Square-ish 900 px JPEG (~80–150 KB) + 300 px thumbnail (~15 KB).
/// Runs in a background isolate on phones so the UI never freezes.
ProductPhoto compressProductPhoto(Uint8List input) {
  final decoded = img.decodeImage(input);
  if (decoded == null) {
    throw const AppException(
      'This photo could not be read. Try another one.',
      'यह फ़ोटो नहीं खुल पाई। दूसरी फ़ोटो चुनें।',
    );
  }
  final upright = img.bakeOrientation(decoded);
  img.Image fit(int max) => upright.width >= upright.height
      ? (upright.width > max ? img.copyResize(upright, width: max, interpolation: img.Interpolation.average) : upright)
      : (upright.height > max
            ? img.copyResize(upright, height: max, interpolation: img.Interpolation.average)
            : upright);
  return ProductPhoto(
    full: Uint8List.fromList(img.encodeJpg(fit(900), quality: 78)),
    thumb: Uint8List.fromList(img.encodeJpg(fit(300), quality: 72)),
  );
}
