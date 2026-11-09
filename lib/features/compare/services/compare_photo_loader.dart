import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';

/// 공유 이미지를 캡처하기 전에 사진을 디코딩해 두는 경계.
///
/// 2단계 공유에서는 캡처할 구성이 화면 뒤에 가려져 있어, 한 프레임만 기다리고
/// 캡처하면 아직 읽히지 않은 사진이 빈 칸으로 찍힌 채 "성공"이 될 수 있다.
/// 캡처 전에 두 사진을 끝까지 읽고, 읽지 못하면 예외를 던져 실패와 재시도로
/// 보낸다. 테스트에서는 실제 파일 I/O 없이 교체한다.
typedef ComparePhotoLoader =
    Future<void> Function(BuildContext context, BodyPhoto photo);

final comparePhotoLoaderProvider = Provider<ComparePhotoLoader>(
  (ref) => precacheComparePhoto,
);

/// [ComparePhotoPane]의 `Image.file`과 같은 캐시 키(FileImage, 배율 1)로
/// 읽어 두므로 캡처 프레임에서 바로 그려진다.
Future<void> precacheComparePhoto(BuildContext context, BodyPhoto photo) async {
  Object? failure;
  await precacheImage(
    FileImage(File(photo.filePath)),
    context,
    onError: (error, _) => failure = error,
  );
  if (failure != null) throw failure!;
}
