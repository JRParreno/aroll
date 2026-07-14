import 'dart:convert';
import 'dart:typed_data';

Uint8List? dataUriBytes(String? value) {
  if (value == null || !value.startsWith('data:image/')) return null;
  final commaIndex = value.indexOf(',');
  if (commaIndex < 0 || commaIndex == value.length - 1) return null;
  try {
    return base64Decode(value.substring(commaIndex + 1));
  } on FormatException {
    return null;
  }
}
