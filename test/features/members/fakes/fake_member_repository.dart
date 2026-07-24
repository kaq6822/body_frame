import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/repositories/member_repository.dart';

/// ProviderScope override로 교체하는 위젯 테스트용 인메모리 [MemberRepository].
class FakeMemberRepository implements MemberRepository {
  final Map<String, Member> _store = {};

  @override
  Future<List<MemberListItem>> list({
    String? query,
    MemberSort sort = MemberSort.recentShot,
  }) async {
    var values = _store.values.where((m) {
      if (query == null || query.trim().isEmpty) return true;
      return m.name.contains(query.trim());
    }).toList();

    switch (sort) {
      case MemberSort.name:
        values.sort((a, b) => a.name.compareTo(b.name));
        break;
      case MemberSort.registeredAt:
      case MemberSort.recentShot:
        values.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }

    return values
        .map((m) => MemberListItem(member: m, recordCount: 0, lastShotAt: null))
        .toList();
  }

  @override
  Future<Member?> getById(String id) async => _store[id];

  @override
  Future<void> insert(Member member) async => _store[member.id] = member;

  @override
  Future<void> update(Member member) async => _store[member.id] = member;

  @override
  Future<void> delete(String id) async => _store.remove(id);
}
