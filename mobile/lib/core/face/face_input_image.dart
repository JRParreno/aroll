import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Android [ImageFormat.NV21]. The installed ML Kit byte converter accepts
/// this and YV12 only. It rejects YUV_420_888 (format 35).
const nv21ImageFormat = 17;

/// Android [ImageFormat.YUV_420_888].
const yuv420ImageFormat = 35;

/// One camera color plane, using the fields `camera_android` actually sends.
class FacePlaneBytes {
  const FacePlaneBytes({
    required this.bytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
  });

  final Uint8List bytes;
  final int bytesPerRow;
  final int? bytesPerPixel;
}

/// One camera frame prepared for ML Kit, plus the size the face box uses.
class CameraFaceFrame {
  const CameraFaceFrame({
    required this.input,
    required this.analysisSize,
    required this.rotationDegrees,
  });

  final InputImage input;

  /// Width and height of the space ML Kit uses for the face box.
  ///
  /// For Android rotations of 90 and 270, the official ML Kit Flutter painter
  /// treats box x as ranging over the original image height. [analysisSize]
  /// follows that same space. It is not the size sent to the detector.
  final Size analysisSize;

  final int rotationDegrees;
}

class CameraFaceConversion {
  const CameraFaceConversion({this.frame, this.skipReason});

  final CameraFaceFrame? frame;
  final String? skipReason;
}

const _orientationCompensation = <DeviceOrientation, int>{
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

/// Format requested from the camera for live face detection.
///
/// Android must be [ImageFormatGroup.yuv420]. `camera_android` 0.10.12 turns
/// an NV21 request into YUV_420_888, then its fast path copies the Y plane
/// with `buffer.get(out, 0, width * height)` and ignores Y row padding.
/// The result is still labeled packed NV21, so ML Kit can see a scrambled
/// frame while the preview, which uses a different surface, stays correct.
ImageFormatGroup faceStreamImageFormat({required bool android}) {
  return android ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888;
}

/// Why a single Android plane cannot be treated as packed NV21.
///
/// A valid NV21 plane has raw format 17, row stride equal to the width, and
/// at least `width * height * 3 / 2` bytes. This does not repair a buffer
/// that the camera plugin already scrambled before setting those fields.
String? androidNv21RejectReason({
  required int rawFormat,
  required int planes,
  required int width,
  required int height,
  required int bytesLength,
  required int bytesPerRow,
}) {
  if (planes != 1) {
    return 'expected 1 NV21 plane, got $planes';
  }
  if (rawFormat != nv21ImageFormat) {
    return 'format $rawFormat is not NV21';
  }
  if (width <= 0 || height <= 0) {
    return 'invalid size ${width}x$height';
  }
  if (width.isOdd || height.isOdd) {
    return 'NV21 size ${width}x$height is not even';
  }
  final packed = width * height * 3 ~/ 2;
  if (bytesLength < packed) {
    return 'NV21 length $bytesLength is shorter than $packed';
  }
  if (bytesPerRow != width) {
    return 'NV21 row stride $bytesPerRow does not match width $width';
  }
  return null;
}

/// Packs Android YUV_420_888 into NV21 using each plane's real strides.
///
/// Y is written tightly. U and V are 2x subsampled and interleaved as VU.
/// A sample at row `r`, column `c` is `bytes[r * bytesPerRow + c * pixelStride]`.
/// Returns a skip reason when that index would fall outside a plane.
String? yuv420888ToNv21({
  required int width,
  required int height,
  required FacePlaneBytes y,
  required FacePlaneBytes u,
  required FacePlaneBytes v,
  required Uint8List out,
}) {
  if (width <= 0 || height <= 0) {
    return 'invalid size ${width}x$height';
  }
  if (width.isOdd || height.isOdd) {
    return 'YUV_420_888 size ${width}x$height is not even';
  }
  final packed = width * height * 3 ~/ 2;
  if (out.length != packed) {
    return 'NV21 output length ${out.length} is not $packed';
  }
  final yPixel = y.bytesPerPixel;
  final uPixel = u.bytesPerPixel;
  final vPixel = v.bytesPerPixel;
  if (yPixel == null || uPixel == null || vPixel == null) {
    return 'YUV_420_888 plane is missing its pixel stride';
  }
  if (y.bytesPerRow <= 0 || u.bytesPerRow <= 0 || v.bytesPerRow <= 0) {
    return 'YUV_420_888 row stride must be positive';
  }
  if (yPixel <= 0 || uPixel <= 0 || vPixel <= 0) {
    return 'YUV_420_888 pixel stride must be positive';
  }

  final chromaWidth = width ~/ 2;
  final chromaHeight = height ~/ 2;
  final ySize = width * height;
  for (var row = 0; row < height; row++) {
    final rowStart = row * y.bytesPerRow;
    final outRow = row * width;
    for (var col = 0; col < width; col++) {
      final index = rowStart + col * yPixel;
      if (index < 0 || index >= y.bytes.length) {
        return 'Y plane read past buffer at $index';
      }
      out[outRow + col] = y.bytes[index];
    }
  }
  for (var row = 0; row < chromaHeight; row++) {
    final uRow = row * u.bytesPerRow;
    final vRow = row * v.bytesPerRow;
    for (var col = 0; col < chromaWidth; col++) {
      final uIndex = uRow + col * uPixel;
      final vIndex = vRow + col * vPixel;
      if (uIndex < 0 || uIndex >= u.bytes.length) {
        return 'U plane read past buffer at $uIndex';
      }
      if (vIndex < 0 || vIndex >= v.bytes.length) {
        return 'V plane read past buffer at $vIndex';
      }
      final chroma = row * chromaWidth + col;
      out[ySize + chroma * 2] = v.bytes[vIndex];
      out[ySize + chroma * 2 + 1] = u.bytes[uIndex];
    }
  }
  return null;
}

/// Builds the Android [InputImage] from the planes the camera plugin delivered.
///
/// YUV_420_888 is converted here. An already packed NV21 plane is copied only
/// when its length and row stride match the packed layout. Any other format
/// is skipped instead of being relabeled.
CameraFaceConversion androidFaceFrame({
  required int rawFormat,
  required int width,
  required int height,
  required List<FacePlaneBytes> planes,
  required InputImageRotation rotation,
}) {
  final Uint8List bytes;
  if (rawFormat == yuv420ImageFormat) {
    if (planes.length != 3) {
      return CameraFaceConversion(
        skipReason: 'YUV_420_888 expected 3 planes, got ${planes.length}',
      );
    }
    if (width <= 0 || height <= 0) {
      return CameraFaceConversion(
        skipReason: 'invalid YUV_420_888 size ${width}x$height',
      );
    }
    if (width.isOdd || height.isOdd) {
      return CameraFaceConversion(
        skipReason: 'YUV_420_888 size ${width}x$height is not even',
      );
    }
    final packed = Uint8List(width * height * 3 ~/ 2);
    final reject = yuv420888ToNv21(
      width: width,
      height: height,
      y: planes[0],
      u: planes[1],
      v: planes[2],
      out: packed,
    );
    if (reject != null) return CameraFaceConversion(skipReason: reject);
    bytes = packed;
  } else if (rawFormat == nv21ImageFormat) {
    final plane = planes.isEmpty ? null : planes.first;
    final reject = androidNv21RejectReason(
      rawFormat: rawFormat,
      planes: planes.length,
      width: width,
      height: height,
      bytesLength: plane?.bytes.length ?? 0,
      bytesPerRow: plane?.bytesPerRow ?? 0,
    );
    if (reject != null) return CameraFaceConversion(skipReason: reject);
    final packedLength = width * height * 3 ~/ 2;
    bytes = Uint8List(packedLength)
      ..setRange(0, packedLength, plane!.bytes);
  } else {
    return CameraFaceConversion(
      skipReason: 'format $rawFormat is not supported',
    );
  }

  final imageWidth = width.toDouble();
  final imageHeight = height.toDouble();
  return CameraFaceConversion(
    frame: CameraFaceFrame(
      input: InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(imageWidth, imageHeight),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: width,
        ),
      ),
      analysisSize: faceAnalysisSize(
        width: imageWidth,
        height: imageHeight,
        rotation: rotation,
      ),
      rotationDegrees: rotation.rawValue,
    ),
  );
}

/// Size used when comparing a face box with the camera frame.
Size faceAnalysisSize({
  required double width,
  required double height,
  required InputImageRotation rotation,
}) {
  final upright = rotation == InputImageRotation.rotation90deg ||
      rotation == InputImageRotation.rotation270deg;
  return upright ? Size(height, width) : Size(width, height);
}

String facePlaneLayout(List<Plane> planes) {
  const names = ['y', 'u', 'v'];
  if (planes.isEmpty) return 'none';
  return [
    for (var i = 0; i < planes.length; i++)
      '${i < names.length ? names[i] : 'p$i'}:'
          'row=${planes[i].bytesPerRow},'
          'pix=${planes[i].bytesPerPixel ?? '-'},'
          'len=${planes[i].bytes.length}',
  ].join(' ');
}

/// Copy a camera frame into an ML Kit image and return immediately.
///
/// [skipReason] is set when the buffer cannot be described as packed NV21.
/// YUV bytes are copied into a new buffer so the camera can reuse its own.
CameraFaceConversion cameraFaceFrame(
  CameraImage image,
  CameraController controller,
) {
  if (image.planes.isEmpty) {
    return const CameraFaceConversion(skipReason: 'camera frame has no planes');
  }

  final camera = controller.description;
  final rotation = Platform.isAndroid
      ? _androidRotation(camera, controller.value.deviceOrientation)
      : InputImageRotationValue.fromRawValue(camera.sensorOrientation);
  if (rotation == null) {
    return const CameraFaceConversion(
      skipReason: 'camera rotation is not supported',
    );
  }

  if (Platform.isAndroid) {
    final raw = image.format.raw;
    if (raw is! int) {
      return const CameraFaceConversion(
        skipReason: 'camera format is not an Android image format',
      );
    }
    return androidFaceFrame(
      rawFormat: raw,
      width: image.width,
      height: image.height,
      planes: [
        for (final plane in image.planes)
          FacePlaneBytes(
            bytes: plane.bytes,
            bytesPerRow: plane.bytesPerRow,
            bytesPerPixel: plane.bytesPerPixel,
          ),
      ],
      rotation: rotation,
    );
  }

  final plane = image.planes.first;
  final width = image.width.toDouble();
  final height = image.height.toDouble();
  return CameraFaceConversion(
    frame: CameraFaceFrame(
      input: InputImage.fromBytes(
        bytes: Uint8List.fromList(plane.bytes),
        metadata: InputImageMetadata(
          size: Size(width, height),
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: plane.bytesPerRow,
        ),
      ),
      analysisSize: faceAnalysisSize(
        width: width,
        height: height,
        rotation: rotation,
      ),
      rotationDegrees: rotation.rawValue,
    ),
  );
}

InputImageRotation? _androidRotation(
  CameraDescription camera,
  DeviceOrientation orientation,
) {
  final compensation = _orientationCompensation[orientation] ?? 0;
  final sensor = camera.sensorOrientation;
  final degrees = camera.lensDirection == CameraLensDirection.front
      ? (sensor + compensation) % 360
      : (sensor - compensation + 360) % 360;
  return InputImageRotationValue.fromRawValue(degrees);
}
