import '../../core/models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import 'member.dart';
import 'member_repository.dart';

final memberRepositoryProvider = Provider<MemberRepository>(
  (ref) => SqliteMemberRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(photoStorageServiceProvider),
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

/// 회원 상세의 "바로 촬영"이 새 레슨 화면에 촬영부터 시작하라고 알리는 값.
///
/// 회원 id를 넣고 `/members/{id}/lessons/new`로 이동하면, 새 레슨 화면이 첫
/// 프레임 뒤에 값을 비우고 촬영 흐름을 연다. 라우트 인자를 늘리지 않으려고 쓴다.
final quickCaptureRequestProvider = StateProvider<String?>((ref) => null);
