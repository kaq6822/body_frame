import '../../core/models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import 'member.dart';
import 'member_repository.dart';

final memberRepositoryProvider = Provider<MemberRepository>(
  (ref) => SqliteMemberRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(photoStorageServiceProvider),
    ref.watch(videoStorageServiceProvider),
  ),
);
final membersProvider = FutureProvider<List<Member>>(
  (ref) => ref.watch(memberRepositoryProvider).list(),
);

/// Inject a stable clock in tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Null context is reserved for old standalone capture routes.
class LessonCaptureContext {
  final String memberId;
  final String? baselineRecordId;
  final bool useBaseline;
  final Map<BodyDirection, String>? baselinePhotos;

  /// 카메라 HUD 표시용. 실제 레슨 일시와 구분 키(`phases`의 키: before/after/regular).
  final DateTime? lessonAt;
  final String? phase;
  const LessonCaptureContext(
    this.memberId, {
    this.baselineRecordId,
    this.useBaseline = true,
    this.baselinePhotos,
    this.lessonAt,
    this.phase,
  });
}

final lessonCaptureContextProvider = StateProvider<LessonCaptureContext?>(
  (ref) => null,
);

/// 레슨 편집 화면을 열자마자 사진 촬영이나 동영상 촬영부터 시작하라는 요청.
///
/// 회원 상세의 "사진 촬영"·"동영상 촬영", 레슨 상세의 "동영상 추가"가 값을 넣고
/// 편집 화면으로 이동한다. 편집 화면은 회원과 레슨이 맞으면 첫 프레임 뒤에 값을
/// 비우고 해당 촬영을 연다. 라우트 인자를 늘리지 않으려고 쓴다.
class QuickCaptureRequest {
  final String memberId;

  /// 기존 레슨에 더할 때의 레슨 id. 새 레슨이면 null.
  final String? recordId;
  final bool video;

  const QuickCaptureRequest({
    required this.memberId,
    this.recordId,
    this.video = false,
  });

  @override
  bool operator ==(Object other) =>
      other is QuickCaptureRequest &&
      other.memberId == memberId &&
      other.recordId == recordId &&
      other.video == video;

  @override
  int get hashCode => Object.hash(memberId, recordId, video);
}

final quickCaptureRequestProvider = StateProvider<QuickCaptureRequest?>(
  (ref) => null,
);
