import 'package:flutter/widgets.dart' show Matrix4, Size;

import '../../core/models/models.dart';

/// 비교 이미지 생성의 대기/진행/성공/실패 상태.
enum CompareExportStatus { idle, generating, success, failure }

/// 전후 사진 비교 화면(compareView)에서 이미지 생성 화면(compareExport)으로
/// 전달하는 스냅샷.
///
/// go_router의 `extra`로 전달한다(경로 파라미터로 표현하기 어려운 확대/이동
/// 행렬과 격자 설정을 그대로 옮기기 위함). 화면에서 확인한 구도와 생성 이미지
/// 구도가 정확히 일치해야 하므로, 비교 화면에서 사용자가
/// 조정한 확대/이동 값([beforeMatrix]/[afterMatrix])을 그대로 재사용한다.
class CompareExportRequest {
  final Member? member;
  final PhotoRecord beforeRecord;
  final PhotoRecord afterRecord;
  final BodyPhoto beforePhoto;
  final BodyPhoto afterPhoto;
  final BodyDirection direction;

  /// 비교 화면에서 사용자가 조정한 확대/이동 상태(스냅샷, 비교 화면과 독립).
  final Matrix4 beforeMatrix;
  final Matrix4 afterMatrix;

  /// 비교 화면에서 사용하던 격자 설정과 표시 여부(초기값 제안용).
  final GridSettings grid;
  final bool showGrid;

  /// 비교 화면에서 실제 렌더링된 사진 프레임의 논리 크기.
  ///
  /// [beforeMatrix]/[afterMatrix]는 pane 로컬 픽셀 좌표 기준이므로, 생성
  /// 화면이 다른 크기의 pane에 같은 행렬을 적용하면 구도가 달라진다.
  /// 생성 화면은 이 크기로 사진 프레임을 고정 렌더링해
  /// 화면 구도와 생성 이미지 구도를 픽셀 단위로 일치시킨다.
  final Size? panePhotoSize;

  const CompareExportRequest({
    required this.member,
    required this.beforeRecord,
    required this.afterRecord,
    required this.beforePhoto,
    required this.afterPhoto,
    required this.direction,
    required this.beforeMatrix,
    required this.afterMatrix,
    required this.grid,
    required this.showGrid,
    this.panePhotoSize,
  });
}
