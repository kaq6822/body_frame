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

  /// 앱 전용 저장소 내 원본 이미지 로컬 파일 경로.
  final String filePath;

  final BodyDirection direction;

  /// 원본 이미지 픽셀 너비.
  final int width;

  /// 원본 이미지 픽셀 높이.
  final int height;

  /// EXIF 기반 회전 정보(1~8). 표시할 때 올바르게 반영한다.
  final int orientation;

  /// 촬영 당시 사용한 격자 설정(재현용).
  final GridSettings gridSettings;

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
    this.memo,
    required this.createdAt,
  });

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
      memo: map['memo'] as String?,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  @override
  bool operator ==(Object other) => other is BodyPhoto && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
