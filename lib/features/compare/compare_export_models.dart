import 'package:flutter/widgets.dart' show Matrix4, Size;

import '../../core/models/models.dart';

/// 비교 이미지 생성의 대기/진행/성공/실패 상태.
enum CompareExportStatus { idle, generating, success, failure }

/// 비교 화면과 생성 이미지가 공유하는 표시 방식.
enum CompareMode {
  sideBySide,
  overlay,
  slider;

  String get key => name;

  String get label {
    switch (this) {
      case CompareMode.sideBySide:
        return '좌우 비교';
      case CompareMode.overlay:
        return '겹쳐 보기';
      case CompareMode.slider:
        return '슬라이더 비교';
    }
  }
}

/// 전후 사진 비교 화면(compareView)에서 이미지 생성 화면(compareExport)으로
/// 전달하는 스냅샷.
///
/// go_router의 `extra`로 전달한다(경로 파라미터로 표현하기 어려운 확대/이동
/// 행렬과 격자 설정을 그대로 옮기기 위함). 화면에서 확인한 구도와 생성 이미지
/// 구도가 정확히 일치해야 하므로, 비교 화면에서 사용자가
/// 조정한 확대/이동 값([beforeMatrix]/[afterMatrix])을 그대로 재사용한다.
class CompareExportRequest {
  final PhotoRecord beforeRecord;
  final PhotoRecord afterRecord;
  final BodyPhoto beforePhoto;
  final BodyPhoto afterPhoto;
  final BodyDirection direction;

  /// 비교 화면에서 사용자가 조정한 확대/이동 상태(스냅샷, 비교 화면과 독립).
  final Matrix4 beforeMatrix;
  final Matrix4 afterMatrix;

  /// 비교 화면에서 사용하던 격자 설정(초기값 제안용).
  final GridSettings grid;

  /// 비교 화면에서 사용자가 **직접 고른** 격자 표시 여부. null이면 고른 적이
  /// 없다는 뜻이며, 생성 화면은 저장된 기본 내보내기 옵션을 그대로 쓴다.
  /// 화면 기본값만으로 사용자가 저장해 둔 설정을 덮어쓰지 않기 위한 구분이다.
  final bool? showGrid;

  /// 화면에서 선택한 비교 방식과 해당 방식의 조절값.
  final CompareMode mode;
  final double overlayOpacity;
  final double sliderPosition;

  /// 비교 화면에서 실제 렌더링된 사진 프레임의 논리 크기.
  ///
  /// [beforeMatrix]/[afterMatrix]는 pane 로컬 픽셀 좌표 기준이므로, 생성
  /// 화면이 다른 크기의 pane에 같은 행렬을 적용하면 구도가 달라진다.
  /// 생성 화면은 이 크기로 사진 프레임을 고정 렌더링해
  /// 화면 구도와 생성 이미지 구도를 픽셀 단위로 일치시킨다.
  final Size? panePhotoSize;

  const CompareExportRequest({
    required this.beforeRecord,
    required this.afterRecord,
    required this.beforePhoto,
    required this.afterPhoto,
    required this.direction,
    required this.beforeMatrix,
    required this.afterMatrix,
    required this.grid,
    this.showGrid,
    this.mode = CompareMode.sideBySide,
    this.overlayOpacity = 0.5,
    this.sliderPosition = 0.5,
    this.panePhotoSize,
  });
}
