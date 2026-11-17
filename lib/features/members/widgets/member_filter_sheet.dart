import 'package:flutter/material.dart';
import '../../../core/korean_text.dart';
import '../../../core/theme/app_tokens.dart';
import '../../records/providers/records_providers.dart';
import '../member.dart';
import '../ui.dart';
import 'record_range_calendar.dart';

/// 기록 목록의 회원 필터 값. null·빈 문자열은 전체, 'unlinked'는 회원 미연결이다.
const unlinkedMemberFilter = 'unlinked';

/// [recordMemberId]를 가진 기록이 회원 필터 [filter]에 들어가는지.
bool matchesMemberFilter(String? recordMemberId, String? filter) =>
    filter == null ||
    filter.isEmpty ||
    (filter == unlinkedMemberFilter
        ? recordMemberId == null
        : recordMemberId == filter);

/// 회원 선택 시트의 한 줄: 회원과 그 회원의 기록 수·최근 레슨 일시.
class MemberFilterEntry {
  final Member member;
  final int count;
  final DateTime? latest;
  const MemberFilterEntry(this.member, this.count, this.latest);
}

/// 회원 선택 시트 순서. 최근 레슨이 늦은 회원부터, 기록이 없는 회원은 맨 뒤
/// (그 안에서는 이름순)에 둔다.
List<MemberFilterEntry> memberFilterEntries(
  List<Member> members,
  Iterable<RecordWithPhotos> records,
) {
  final counts = <String, int>{};
  final latest = <String, DateTime>{};
  for (final item in records) {
    final id = item.record.memberId;
    if (id == null) continue;
    counts[id] = (counts[id] ?? 0) + 1;
    final at = item.record.shotAt;
    final prev = latest[id];
    if (prev == null || at.isAfter(prev)) latest[id] = at;
  }
  final entries = [
    for (final m in members)
      MemberFilterEntry(m, counts[m.id] ?? 0, latest[m.id]),
  ];
  entries.sort((a, b) {
    final la = a.latest;
    final lb = b.latest;
    if (la != null && lb != null && la != lb) return lb.compareTo(la);
    if (la == null && lb != null) return 1;
    if (la != null && lb == null) return -1;
    return a.member.name.compareTo(b.member.name);
  });
  return entries;
}

/// 회원 필터를 고르는 시트. 고른 필터 값('' = 전체 회원)을 돌려주고, 닫기만
/// 하면 null이다.
Future<String?> showMemberFilterSheet(
  BuildContext context, {
  required List<Member> members,
  required List<RecordWithPhotos> records,
  required String? selected,
  required DateTime now,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => MemberFilterSheet(
    members: members,
    records: records,
    selected: selected,
    now: now,
  ),
);

class MemberFilterSheet extends StatefulWidget {
  final List<Member> members;
  final List<RecordWithPhotos> records;
  final String? selected;
  final DateTime now;
  const MemberFilterSheet({
    super.key,
    required this.members,
    required this.records,
    required this.selected,
    required this.now,
  });

  @override
  State<MemberFilterSheet> createState() => _MemberFilterSheetState();
}

class _MemberFilterSheetState extends State<MemberFilterSheet> {
  String query = '';
  late final entries = memberFilterEntries(widget.members, widget.records);
  late final unlinkedCount = widget.records
      .where((r) => r.record.memberId == null)
      .length;

  String get _selected => widget.selected ?? '';

  Widget _iconAvatar(IconData icon) => ExcludeSemantics(
    child: CircleAvatar(
      radius: 20,
      backgroundColor: context.colors.surfaceContainerHigh,
      foregroundColor: context.colors.onSurfaceVariant,
      child: Icon(icon, size: 20),
    ),
  );

  Widget _row({
    required String id,
    required String value,
    required Widget leading,
    required String title,
    required String subtitle,
  }) {
    final selected = _selected == value;
    final colors = context.colors;
    return mark(
      id,
      ListTile(
        selected: selected,
        selectedColor: colors.onSurface,
        selectedTileColor: colors.primaryContainer.withValues(alpha: 0.4),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp4),
        leading: leading,
        title: Text(
          title,
          style: context.texts.titleSmall?.copyWith(
            fontWeight: selected ? FontWeight.w700 : null,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: context.numericTexts.bodySmall.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        trailing: selected ? Icon(Icons.check, color: colors.primary) : null,
        onTap: () => Navigator.pop(context, value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final q = query.trim().toLowerCase();
    final shown = q.isEmpty
        ? entries
        : entries
              .where((e) => e.member.name.toLowerCase().contains(q))
              .toList();
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
    return mark(
      'lessons.member.sheet',
      Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp4),
                child: Semantics(
                  header: true,
                  child: Text('회원 선택', style: context.texts.titleLarge),
                ),
              ),
              const SizedBox(height: AppSpacing.sp3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp4),
                child: mark(
                  'lessons.member.sheet.search',
                  TextField(
                    onChanged: (v) => setState(() => query = v),
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: '회원 이름 검색',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sp2),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.only(
                    bottom:
                        AppSpacing.sp4 + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    if (q.isEmpty) ...[
                      _row(
                        id: 'lessons.member.option.all',
                        value: '',
                        leading: _iconAvatar(Icons.groups_outlined),
                        title: '전체 회원',
                        subtitle: '기록 ${widget.records.length}개',
                      ),
                      if (unlinkedCount > 0)
                        _row(
                          id: 'lessons.member.option.unlinked',
                          value: unlinkedMemberFilter,
                          leading: _iconAvatar(Icons.link_off),
                          title: '회원 미연결',
                          subtitle: '기록 $unlinkedCount개',
                        ),
                      if (entries.isNotEmpty)
                        const Divider(
                          height: AppSpacing.sp4,
                          indent: AppSpacing.sp4,
                          endIndent: AppSpacing.sp4,
                        ),
                    ],
                    for (final e in shown)
                      _row(
                        id: 'lessons.member.option.${e.member.id}',
                        value: e.member.id,
                        leading: MemberAvatar(
                          e.member.name,
                          active: e.latest != null,
                        ),
                        title: e.member.name,
                        subtitle: e.latest == null
                            ? '기록 없음'
                            : '기록 ${e.count}개 · 최근 ${recordDayLabel(e.latest!, widget.now)}',
                      ),
                    if (q.isNotEmpty && shown.isEmpty)
                      mark(
                        'lessons.member.sheet.empty',
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.sp6),
                          child: Text(
                            keepPhrasesWhole("'${query.trim()}'와 일치하는 회원이 없어요"),
                            textAlign: TextAlign.center,
                            style: context.texts.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
