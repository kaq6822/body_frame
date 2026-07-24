import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/repositories/member_repository.dart';
import '../../core/router/app_routes.dart';
import 'providers/members_providers.dart';
import 'widgets/async_status.dart';

/// 회원 목록 화면.
///
/// 이름 검색, 3종 정렬(최근 촬영순/이름순/등록일순), 새 회원 등록 버튼과
/// 빈 목록 상태 UI를 제공한다.
class MembersListScreen extends ConsumerStatefulWidget {
  static const screenId = 'screen.members.list';

  const MembersListScreen({super.key});

  @override
  ConsumerState<MembersListScreen> createState() => _MembersListScreenState();
}

class _MembersListScreenState extends ConsumerState<MembersListScreen> {
  late final TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(
      text: ref.read(memberSearchQueryProvider),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    ref.read(memberSearchQueryProvider.notifier).state = value;
    setState(() {}); // suffixIcon(지우기 버튼) 표시 갱신.
  }

  @override
  Widget build(BuildContext context) {
    final sort = ref.watch(memberSortProvider);
    final membersAsync = ref.watch(membersListProvider);

    return Semantics(
      identifier: MembersListScreen.screenId,
      container: true,
      label: '회원 목록',
      child: Scaffold(
        key: const ValueKey(MembersListScreen.screenId),
        appBar: AppBar(
          title: const Text('회원 목록'),
          actions: [
            Semantics(
              identifier: 'members.sort.button',
              button: true,
              label: '정렬 방식 선택 (현재: ${sort.label})',
              child: PopupMenuButton<MemberSort>(
                key: const ValueKey('members.sort.button'),
                icon: const Icon(Icons.sort),
                initialValue: sort,
                onSelected: (value) =>
                    ref.read(memberSortProvider.notifier).state = value,
                itemBuilder: (context) => MemberSort.values
                    .map(
                      (s) => PopupMenuItem<MemberSort>(
                        value: s,
                        key: ValueKey('members.sort.option.${s.name}'),
                        child: Semantics(
                          identifier: 'members.sort.option.${s.name}',
                          selected: s == sort,
                          label: s.label,
                          child: Text(s.label),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            Semantics(
              identifier: 'members.settings.button',
              button: true,
              label: '앱 설정',
              child: IconButton(
                key: const ValueKey('members.settings.button'),
                tooltip: '앱 설정',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => context.pushNamed(AppRoutes.settings),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Semantics(
                identifier: 'members.search.field',
                textField: true,
                label: '이름 검색',
                child: TextField(
                  key: const ValueKey('members.search.field'),
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: '이름으로 검색',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            key: const ValueKey('members.search.clear.button'),
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              _onSearchChanged('');
                            },
                          ),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ),
            Expanded(
              child: AsyncValueView<List<MemberListItem>>(
                value: membersAsync,
                statusId: '${MembersListScreen.screenId}.status',
                onRetry: () => ref.invalidate(membersListProvider),
                builder: (items) {
                  if (items.isEmpty) {
                    return Center(
                      child: Semantics(
                        identifier: 'members.list.empty',
                        label: '등록된 회원 없음',
                        child: Padding(
                          key: const ValueKey('members.list.empty'),
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.people_outline, size: 48),
                              const SizedBox(height: 12),
                              Text(
                                _searchCtrl.text.isEmpty
                                    ? '등록된 회원이 없습니다.\n새 회원을 등록해 보세요.'
                                    : '검색 결과가 없습니다.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    key: const ValueKey('members.list'),
                    itemCount: items.length,
                    itemBuilder: (context, index) =>
                        _MemberTile(item: items[index], index: index),
                  );
                },
              ),
            ),
          ],
        ),
        floatingActionButton: Semantics(
          identifier: 'members.add.button',
          button: true,
          label: '새 회원 등록',
          child: FloatingActionButton(
            key: const ValueKey('members.add.button'),
            onPressed: () => context.pushNamed(AppRoutes.memberAdd),
            child: const Icon(Icons.add),
          ),
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final MemberListItem item;
  final int index;

  const _MemberTile({required this.item, required this.index});

  @override
  Widget build(BuildContext context) {
    final member = item.member;
    final lastShot = item.lastShotAt;
    final subtitle = [
      lastShot == null
          ? '촬영 기록 없음'
          : '최근 촬영 ${DateFormat('yyyy.MM.dd').format(lastShot)}',
      '기록 ${item.recordCount}건',
      '수정 ${DateFormat('yyyy.MM.dd').format(member.updatedAt)}',
    ].join(' · ');

    return Semantics(
      identifier: 'members.item.$index',
      button: true,
      label: '${member.name}, $subtitle',
      child: ListTile(
        key: ValueKey('members.item.$index'),
        leading: CircleAvatar(
          backgroundImage: member.avatarPath != null
              ? FileImage(File(member.avatarPath!))
              : null,
          child: member.avatarPath == null ? const Icon(Icons.person) : null,
        ),
        title: Text(member.name),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.pushNamed(
          AppRoutes.memberDetail,
          pathParameters: {AppParams.memberId: member.id},
        ),
      ),
    );
  }
}
