import 'body_direction.dart';
import 'grid_settings.dart';

/// 체형 사진.
///
/// 사진 파일 자체는 DB에 저장하지 않고 [filePath]로
/// 로컬 경로와 메타데이터만 관리한다. 원본은 절대 변형/크롭하지 않으며
/// [width]/[height]/[orientation]으로 올바른 표시 정보를 유지한다.
class BodyPhoto {
  final String id;

  /// 소속 촬영 기록 식별자.
  final String recordId;

  /// 실행 중 해석된 앱 전용 저장소 내 원본 이미지 절대경로.
  ///
  /// 영속화할 때는 리포지토리가 앱 저장소 기준 상대경로로 변환한다.
  final String filePath;

  final BodyDirection direction;

  /// 원본 이미지 픽셀 너비.
  final int width;

  /// 원본 이미지 픽셀 높이.
  final int height;

  /// EXIF 기반 회전 정보(1~8). 표시할 때 올바르게 반영한다.
  final int orientation;

  /// 현재 이 사진에 적용된 격자 설정.
  ///
  /// 격자는 원본 픽셀에 굽지 않고 메타데이터로만 남기므로 촬영 후에도 바꿀 수
  /// 있다. 화면 표시는 항상 오버레이이고, 한 장으로 합치는 것은 내보내기·공유
  /// 순간뿐이다.
  final GridSettings gridSettings;

  /// 촬영 당시 격자 설정. null이면 [gridSettings]와 같다고 본다.
  ///
  /// [captureGridSettings]로 읽는다. 되돌리기를 위해 보존하는 값이므로 수정
  /// 경로에서 덮어쓰지 않는다.
  final GridSettings? _captureGridSettings;

  /// 사진 메모 (선택).
  final String? memo;

  /// 등록일.
  final DateTime createdAt;

  const BodyPhoto({
    required this.id,
    required this.recordId,
    required this.filePath,
    required this.direction,
    this.width = 0,
    this.height = 0,
    this.orientation = 1,
    this.gridSettings = GridSettings.defaults,
    GridSettings? captureGridSettings,
    this.memo,
    required this.createdAt,
  }) : _captureGridSettings = captureGridSettings;

  /// 촬영 당시 격자 설정. 촬영 후 [gridSettings]를 조정해도 바뀌지 않는다.
  GridSettings get captureGridSettings => _captureGridSettings ?? gridSettings;

  /// 촬영 당시 설정과 다르게 조정된 상태인지. 되돌리기 노출 여부를 정한다.
  bool get isGridEdited => captureGridSettings != gridSettings;

  BodyPhoto copyWith({
    String? recordId,
    String? filePath,
    BodyDirection? direction,
    int? width,
    int? height,
    int? orientation,
    GridSettings? gridSettings,
    String? memo,
    DateTime? createdAt,
  }) {
    return BodyPhoto(
      id: id,
      recordId: recordId ?? this.recordId,
      filePath: filePath ?? this.filePath,
      direction: direction ?? this.direction,
      width: width ?? this.width,
      height: height ?? this.height,
      orientation: orientation ?? this.orientation,
      gridSettings: gridSettings ?? this.gridSettings,
      // 촬영 당시 값은 copyWith로 바꿀 수 없다. 되돌리기의 기준점이므로
      // 수정 경로에서 잃어버리지 않게 항상 그대로 넘긴다.
      captureGridSettings: _captureGridSettings,
      memo: memo ?? this.memo,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'record_id': recordId,
      'file_path': filePath,
      'direction': direction.key,
      'width': width,
      'height': height,
      'orientation': orientation,
      'grid_settings': gridSettings.toJson(),
      'capture_grid_settings': captureGridSettings.toJson(),
      'memo': memo,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory BodyPhoto.fromMap(Map<String, dynamic> map) {
    return BodyPhoto(
      id: map['id'] as String,
      recordId: map['record_id'] as String,
      filePath: map['file_path'] as String,
      direction: BodyDirection.fromKey(map['direction'] as String?),
      width: (map['width'] as int?) ?? 0,
      height: (map['height'] as int?) ?? 0,
      orientation: (map['orientation'] as int?) ?? 1,
      gridSettings: GridSettings.fromJson(map['grid_settings'] as String?),
      // 마이그레이션 이전 행은 이 값이 없다. null로 두면 촬영 당시 설정이
      // 현재 설정과 같다고 해석되어 되돌리기가 노출되지 않는다.
      captureGridSettings: switch (map['capture_grid_settings']) {
        final String json when json.isNotEmpty => GridSettings.fromJson(json),
        _ => null,
      },
      memo: map['memo'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  @override
  bool operator ==(Object other) => other is BodyPhoto && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
