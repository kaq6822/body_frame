import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../records/providers/records_providers.dart';
import 'member_providers.dart';
import 'ui.dart';

class LessonCard extends StatelessWidget {
  final RecordWithPhotos item;
  final String? memberName;
  const LessonCard({super.key, required this.item, this.memberName});
  @override
  Widget build(BuildContext context) => mark(
    'lessons.${item.record.id}.card',
    panel(
      child: InkWell(
        onTap: () => context.push('/lessons/${item.record.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (memberName != null)
              Text(
                memberName!,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            Text(
              lessonDate(item.record.shotAt),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if ((item.record.condition ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(item.record.condition!),
              ),
            if ((item.record.memo ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  item.record.memo!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 12),
            Text(
              item.photos.isEmpty ? '수업 일지' : '체형 사진 ${item.photos.length}장',
            ),
            if (item.photos.isNotEmpty)
              SizedBox(
                height: 112,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: item.photos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => SizedBox(
                    width: 72,
                    child: Column(
                      children: [
                        Expanded(
                          child: Image.file(
                            File(item.photos[i].filePath),
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                        Text(
                          item.photos[i].direction.label,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class LessonRecordsScreen extends ConsumerStatefulWidget {
  const LessonRecordsScreen({super.key});
  @override
  ConsumerState<LessonRecordsScreen> createState() => _LessonRecordsState();
}

class _LessonRecordsState extends ConsumerState<LessonRecordsScreen> {
  String query = '';
  String? memberId;
  DateTimeRange? range;
  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersProvider);
    return mark(
      'screen.lessons.records',
      Scaffold(
        appBar: AppBar(title: const Text('기록')),
        bottomNavigationBar: const MainNavigation(1),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  mark(
                    'lessons.search.field',
                    TextField(
                      onChanged: (v) => setState(() => query = v.toLowerCase()),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: '회원 이름, 메모 검색',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    children: [
                      mark(
                        'lessons.member.filter',
                        DropdownButton<String>(
                          value: memberId,
                          hint: const Text('전체 회원'),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('전체 회원'),
                            ),
                            const DropdownMenuItem(
                              value: 'unlinked',
                              child: Text('회원 미연결'),
                            ),
                            for (final m in members.valueOrNull ?? [])
                              DropdownMenuItem(
                                value: m.id,
                                child: Text(m.name),
                              ),
                          ],
                          onChanged: (v) => setState(() => memberId = v),
                        ),
                      ),
                      mark(
                        'lessons.date.filter',
                        OutlinedButton.icon(
                          onPressed: () async {
                            final r = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                              initialDateRange: range,
                            );
                            if (r != null && mounted) setState(() => range = r);
                          },
                          icon: const Icon(Icons.calendar_month),
                          label: Text(
                            range == null
                                ? '전체 기간'
                                : '${range!.start.month}.${range!.start.day} ~ ${range!.end.month}.${range!.end.day}',
                          ),
                        ),
                      ),
                      if (range != null)
                        TextButton(
                          onPressed: () => setState(() => range = null),
                          child: const Text('기간 초기화'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ref
                  .watch(timelineProvider)
                  .when(
                    loading: () => busy('lessons.records.loading'),
                    error: (_, _) => failure(
                      'lessons.records.error',
                      '기록을 불러오지 못했어요. 검색 조건은 유지돼요.',
                      () => ref.invalidate(timelineProvider),
                    ),
                    data: (items) {
                      if (members.hasError) {
                        return failure(
                          'lessons.members.error',
                          '회원 이름을 불러오지 못했어요.',
                          () => ref.invalidate(membersProvider),
                        );
                      }
                      final names = {
                        for (final m in members.valueOrNull ?? []) m.id: m.name,
                      };
                      final list = items.where((x) {
                        final r = x.record;
                        return (memberId == null ||
                                memberId == '' ||
                                (memberId == 'unlinked'
                                    ? r.memberId == null
                                    : r.memberId == memberId)) &&
                            (range == null ||
                                !r.shotAt.isBefore(range!.start) &&
                                    r.shotAt.isBefore(
                                      range!.end.add(const Duration(days: 1)),
                                    )) &&
                            '${names[r.memberId] ?? r.label ?? ''} ${r.memo ?? ''} ${r.condition ?? ''}'
                                .toLowerCase()
                                .contains(query);
                      }).toList();
                      if (list.isEmpty) {
                        return mark(
                          'lessons.records.empty',
                          const Center(
                            child: Text(
                              '표시할 기록이 없어요.\n회원 화면에서 레슨을 기록해주세요.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                      return ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Text('레슨 기록 ${list.length}개'),
                          const SizedBox(height: 12),
                          for (final item in list)
                            LessonCard(
                              item: item,
                              memberName:
                                  names[item.record.memberId] ??
                                  item.record.label ??
                                  '회원 미연결',
                            ),
                        ],
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
