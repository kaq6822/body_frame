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
  const LessonCaptureContext(
    this.memberId, {
    this.baselineRecordId,
    this.useBaseline = true,
    this.baselinePhotos,
  });
}

final lessonCaptureContextProvider = StateProvider<LessonCaptureContext?>(
  (ref) => null,
);
