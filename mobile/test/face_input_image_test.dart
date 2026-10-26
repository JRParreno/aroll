import 'dart:typed_data';
import 'dart:ui';

import 'package:aroll_mobile/core/face/face_input_image.dart';
import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

void main() {
  test('packed NV21 from a single plane is accepted', () {
    const width = 4;
    const height = 2;
    final source = Uint8List.fromList(List<int>.generate(12, (i) => i + 1));
    final frame = androidFaceFrame(
      rawFormat: nv21ImageFormat,
      width: width,
      height: height,
      planes: [
        FacePlaneBytes(
          bytes: source,
          bytesPerRow: width,
          bytesPerPixel: 1,
        ),
      ],
      rotation: InputImageRotation.rotation270deg,
    );

    expect(frame.skipReason, isNull);
    final input = frame.frame!.input;
    expect(input.bytes, source);
    expect(input.metadata!.format, InputImageFormat.nv21);
    expect(input.metadata!.format.rawValue, nv21ImageFormat);
    expect(input.metadata!.bytesPerRow, width);
    expect(input.metadata!.size, const Size(4, 2));
    expect(input.metadata!.rotation, InputImageRotation.rotation270deg);
    expect(frame.frame!.analysisSize, const Size(2, 4));
    expect(input.bytes, isNot(same(source)));
  });

  test('YUV_420_888 with padded Y rows is packed without the padding', () {
    const width = 4;
    const height = 2;
    final y = Uint8List.fromList([
      1, 2, 3, 4, 9, 9, //
      5, 6, 7, 8,
    ]);
    final u = Uint8List.fromList([11, 12]);
    final v = Uint8List.fromList([21, 22]);

    final frame = androidFaceFrame(
      rawFormat: yuv420ImageFormat,
      width: width,
      height: height,
      planes: [
        FacePlaneBytes(bytes: y, bytesPerRow: 6, bytesPerPixel: 1),
        FacePlaneBytes(bytes: u, bytesPerRow: 2, bytesPerPixel: 1),
        FacePlaneBytes(bytes: v, bytesPerRow: 2, bytesPerPixel: 1),
      ],
      rotation: InputImageRotation.rotation0deg,
    );

    expect(frame.skipReason, isNull);
    expect(
      frame.frame!.input.bytes,
      Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 21, 11, 22, 12]),
    );
    expect(frame.frame!.input.bytes!.length, width * height * 3 ~/ 2);
    expect(frame.frame!.input.metadata!.bytesPerRow, width);
    expect(frame.frame!.analysisSize, const Size(4, 2));
  });

  test('chroma pixel stride greater than one is interleaved as NV21', () {
    final y = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
    final u = Uint8List.fromList([11, 0, 12, 0]);
    final v = Uint8List.fromList([21, 0, 22, 0]);

    final frame = androidFaceFrame(
      rawFormat: yuv420ImageFormat,
      width: 4,
      height: 2,
      planes: [
        FacePlaneBytes(bytes: y, bytesPerRow: 4, bytesPerPixel: 1),
        FacePlaneBytes(bytes: u, bytesPerRow: 4, bytesPerPixel: 2),
        FacePlaneBytes(bytes: v, bytesPerRow: 4, bytesPerPixel: 2),
      ],
      rotation: InputImageRotation.rotation90deg,
    );

    expect(frame.skipReason, isNull);
    expect(
      frame.frame!.input.bytes,
      Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 21, 11, 22, 12]),
    );
    expect(frame.frame!.analysisSize, const Size(2, 4));
    expect(
      frame.frame!.input.metadata!.size,
      const Size(4, 2),
    );
  });

  test('padded chroma rows with pixel stride 2 keep only the real samples', () {
    final y = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
    final u = Uint8List.fromList([11, 0, 12, 0, 9, 9]);
    final v = Uint8List.fromList([21, 0, 22, 0, 8, 8]);
    final frame = androidFaceFrame(
      rawFormat: yuv420ImageFormat,
      width: 4,
      height: 2,
      planes: [
        FacePlaneBytes(bytes: y, bytesPerRow: 4, bytesPerPixel: 1),
        FacePlaneBytes(bytes: u, bytesPerRow: 6, bytesPerPixel: 2),
        FacePlaneBytes(bytes: v, bytesPerRow: 6, bytesPerPixel: 2),
      ],
      rotation: InputImageRotation.rotation0deg,
    );

    expect(frame.skipReason, isNull);
    expect(
      frame.frame!.input.bytes,
      Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 21, 11, 22, 12]),
    );
  });

  test('YUV planes are not concatenated in their original order', () {
    final y = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
    final u = Uint8List.fromList([11, 12]);
    final v = Uint8List.fromList([21, 22]);
    final frame = androidFaceFrame(
      rawFormat: yuv420ImageFormat,
      width: 4,
      height: 2,
      planes: [
        FacePlaneBytes(bytes: y, bytesPerRow: 4, bytesPerPixel: 1),
        FacePlaneBytes(bytes: u, bytesPerRow: 2, bytesPerPixel: 1),
        FacePlaneBytes(bytes: v, bytesPerRow: 2, bytesPerPixel: 1),
      ],
      rotation: InputImageRotation.rotation0deg,
    );

    expect(frame.frame!.input.bytes, isNot(Uint8List.fromList([...y, ...u, ...v])));
  });

  test('odd YUV dimensions are rejected', () {
    final frame = androidFaceFrame(
      rawFormat: yuv420ImageFormat,
      width: 3,
      height: 2,
      planes: [
        FacePlaneBytes(bytes: Uint8List(6), bytesPerRow: 3, bytesPerPixel: 1),
        FacePlaneBytes(bytes: Uint8List(2), bytesPerRow: 2, bytesPerPixel: 1),
        FacePlaneBytes(bytes: Uint8List(2), bytesPerRow: 2, bytesPerPixel: 1),
      ],
      rotation: InputImageRotation.rotation0deg,
    );
    expect(frame.frame, isNull);
    expect(frame.skipReason, contains('not even'));
  });

  test('a YUV frame with the wrong plane count is rejected', () {
    final frame = androidFaceFrame(
      rawFormat: yuv420ImageFormat,
      width: 4,
      height: 2,
      planes: [
        FacePlaneBytes(bytes: Uint8List(8), bytesPerRow: 4, bytesPerPixel: 1),
        FacePlaneBytes(bytes: Uint8List(2), bytesPerRow: 2, bytesPerPixel: 1),
      ],
      rotation: InputImageRotation.rotation0deg,
    );
    expect(frame.skipReason, 'YUV_420_888 expected 3 planes, got 2');
  });

  test('a short Y plane is rejected before it is read past the end', () {
    final frame = androidFaceFrame(
      rawFormat: yuv420ImageFormat,
      width: 4,
      height: 2,
      planes: [
        FacePlaneBytes(bytes: Uint8List(3), bytesPerRow: 4, bytesPerPixel: 1),
        FacePlaneBytes(bytes: Uint8List(2), bytesPerRow: 2, bytesPerPixel: 1),
        FacePlaneBytes(bytes: Uint8List(2), bytesPerRow: 2, bytesPerPixel: 1),
      ],
      rotation: InputImageRotation.rotation0deg,
    );
    expect(frame.frame, isNull);
    expect(frame.skipReason, contains('Y plane read past buffer'));
  });

  test('a missing pixel stride is rejected', () {
    final frame = androidFaceFrame(
      rawFormat: yuv420ImageFormat,
      width: 4,
      height: 2,
      planes: [
        FacePlaneBytes(bytes: Uint8List(8), bytesPerRow: 4, bytesPerPixel: null),
        FacePlaneBytes(bytes: Uint8List(2), bytesPerRow: 2, bytesPerPixel: 1),
        FacePlaneBytes(bytes: Uint8List(2), bytesPerRow: 2, bytesPerPixel: 1),
      ],
      rotation: InputImageRotation.rotation0deg,
    );
    expect(frame.skipReason, contains('pixel stride'));
  });

  test('JPEG and a single non-NV21 plane are not relabeled', () {
    final jpeg = androidFaceFrame(
      rawFormat: 256,
      width: 4,
      height: 2,
      planes: [
        FacePlaneBytes(bytes: Uint8List(8), bytesPerRow: 4, bytesPerPixel: 1),
      ],
      rotation: InputImageRotation.rotation0deg,
    );
    expect(jpeg.skipReason, 'format 256 is not supported');

    final yuvPlane = androidFaceFrame(
      rawFormat: yuv420ImageFormat,
      width: 4,
      height: 2,
      planes: [
        FacePlaneBytes(
          bytes: Uint8List(12),
          bytesPerRow: 4,
          bytesPerPixel: 1,
        ),
      ],
      rotation: InputImageRotation.rotation0deg,
    );
    expect(yuvPlane.skipReason, contains('expected 3 planes'));
  });

  test('a short NV21 buffer is rejected', () {
    final reason = androidNv21RejectReason(
      rawFormat: nv21ImageFormat,
      planes: 1,
      width: 640,
      height: 480,
      bytesLength: 100,
      bytesPerRow: 640,
    );
    expect(reason, contains('shorter than'));
  });

  test('padded NV21 row stride is rejected', () {
    final reason = androidNv21RejectReason(
      rawFormat: nv21ImageFormat,
      planes: 1,
      width: 640,
      height: 480,
      bytesLength: 640 * 480 * 3 ~/ 2,
      bytesPerRow: 768,
    );
    expect(reason, contains('row stride'));
  });

  test('Android face analysis requests YUV_420_888 rather than plugin NV21', () {
    expect(
      faceStreamImageFormat(android: true),
      ImageFormatGroup.yuv420,
    );
    expect(
      faceStreamImageFormat(android: false),
      ImageFormatGroup.bgra8888,
    );
  });
}
