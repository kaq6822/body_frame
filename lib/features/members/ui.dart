import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/status_pill.dart';
import '../../core/widgets/app_confirm_dialog.dart';

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];
String lessonDate(DateTime d) =>
    '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')} (${_weekdays[d.weekday - 1]}) ${d.hour < 12 ? '오전' : '오후'} ${d.hour % 12 == 0 ? 12 : d.hour % 12}:${d.minute.toString().padLeft(2, '0')}';
const phases = {'before': '수업 전', 'after': '수업 후', 'regular': '정기'};
Widget mark(String id, Widget child) => Semantics(
  identifier: id,
  container: true,
  child: KeyedSubtree(key: ValueKey(id), child: child),
);
Widget panel({required Widget child}) => Card(
  margin: const EdgeInsets.only(bottom: AppSpacing.sp4),
  child: Padding(padding: const EdgeInsets.all(AppSpacing.sp4), child: child),
);
Widget section(String title, Widget child) => panel(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Builder(
        builder: (context) =>
            Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      const SizedBox(height: AppSpacing.sp3),
      child,
    ],
  ),
);
Widget input(
  String id,
  TextEditingController controller,
  String label, {
  int lines = 1,
  bool enabled = true,
  String? hint,
  ValueChanged<String>? onChanged,
}) => mark(
  id,
  TextField(
    controller: controller,
    enabled: enabled,
    maxLines: lines,
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: true,
    ),
  ),
);
Widget action(
  String id,
  String label,
  VoidCallback? onPressed, {
  IconData? icon,
}) => mark(
  id,
  FilledButton.icon(
    onPressed: onPressed,
    icon: Icon(icon ?? Icons.check),
    label: Text(label),
  ),
);
Widget failure(String id, String message, VoidCallback retry) => mark(
  id,
  panel(
    child: Column(
      children: [
        Text(message),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: retry,
          icon: const Icon(Icons.refresh),
          label: const Text('다시 시도'),
        ),
      ],
    ),
  ),
);
Widget busy(String id, [String message = '불러오는 중이에요']) => mark(
  id,
  Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(message),
        ],
      ),
    ),
  ),
);

/// 공통 확인 다이얼로그([showAppConfirm])의 짧은 호출 형태.
Future<bool> confirm(
  BuildContext context,
  String title,
  String body, {
  String button = '삭제',
  String cancel = '취소',
  IconData? icon,
  bool destructive = false,
  bool preferCancel = false,
  List<String> summary = const [],
  String? warning,
}) => showAppConfirm(
  context,
  title: title,
  body: body,
  confirmLabel: button,
  cancelLabel: cancel,
  icon: icon,
  destructive: destructive,
  preferCancel: preferCancel,
  summary: summary,
  warning: warning,
);

/// 실제 레슨 일시를 날짜·시각 한 시트에서 고른다. 취소하면 null.
Future<DateTime?> pickLessonDate(BuildContext context, DateTime current) =>
    showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => LessonDateSheet(initial: current),
    );

String _two(int v) => v.toString().padLeft(2, '0');

/// "11.04 오후 3:00" — 목록·요약처럼 좁은 곳의 짧은 일시.
String shortLessonDate(DateTime d) =>
    '${_two(d.month)}.${_two(d.day)} ${d.hour < 12 ? '오전' : '오후'} ${d.hour % 12 == 0 ? 12 : d.hour % 12}:${_two(d.minute)}';

/// "14:55" — 같은 날 안에서 촬영 시각만 보일 때.
String clockTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// 아바타 글자. 한글 세 글자 이상은 성을 뺀 이름 두 글자(김서연 → 서연),
/// 띄어 쓴 영문은 단어 첫 글자 두 개(Lee Test → LT).
String memberInitials(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  final words = trimmed.split(RegExp(r'\s+'));
  if (words.length > 1) {
    return words.take(2).map((w) => w.characters.first).join().toUpperCase();
  }
  final chars = trimmed.characters;
  if (chars.length >= 3) return chars.skip(chars.length - 2).string;
  return trimmed;
}

/// 주의사항의 첫 구절. 목록 칩처럼 한 줄 요약에 쓴다.
String cautionKeyword(String precautions) => precautions
    .split(RegExp(r'[\n·,]'))
    .map((s) => s.trim())
    .firstWhere((s) => s.isNotEmpty, orElse: () => '');

/// "수업 전 4장 · 수업 후 4장". 구분이 하나뿐이면 그 구분만 적는다.
String phaseSummary(Iterable<BodyPhoto> photos) {
  final counts = <String, int>{};
  for (final p in photos) {
    counts[p.phase] = (counts[p.phase] ?? 0) + 1;
  }
  return [
    for (final e in phases.entries)
      if (counts[e.key] != null) '${e.value} ${counts[e.key]}장',
  ].join(' · ');
}

/// 회원 이니셜 아바타. 최근 레슨이 없으면 회색 톤이다.
class MemberAvatar extends StatelessWidget {
  final String name;
  final bool active;
  final double size;
  const MemberAvatar(
    this.name, {
    super.key,
    this.active = true,
    this.size = 40,
  });
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: active
            ? colors.primaryContainer
            : colors.surfaceContainerHigh,
        foregroundColor: active
            ? colors.onPrimaryContainer
            : colors.onSurfaceVariant,
        child: Text(
          memberInitials(name),
          maxLines: 1,
          style: context.texts.labelLarge?.copyWith(
            color: active ? colors.onPrimaryContainer : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 빈 상태·실패 상태. 아이콘 타일 + 제목 + 본문 + 동작 버튼(세로로 가득).
///
/// [compact]면 카드 안에 넣는 작은 형태로, 가운데 정렬·스크롤 없이 그린다.
class EmptyState extends StatelessWidget {
  final String identifier;
  final IconData icon;
  final String title;
  final String? body;
  final List<Widget> actions;
  final bool error;
  final bool compact;
  const EmptyState({
    super.key,
    required this.identifier,
    required this.icon,
    required this.title,
    this.body,
    this.actions = const [],
    this.error = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tile = compact ? 56.0 : 80.0;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: tile,
            height: tile,
            decoration: BoxDecoration(
              color: error ? colors.errorContainer : colors.primaryContainer,
              borderRadius: compact ? AppRadius.fullAll : AppRadius.xlAll,
            ),
            child: Icon(
              icon,
              size: tile / 2,
              color: error ? colors.onErrorContainer : colors.primary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sp4),
        Text(
          title,
          textAlign: TextAlign.center,
          style:
              (compact ? context.texts.titleMedium : context.texts.titleLarge)
                  ?.copyWith(color: colors.onSurface),
        ),
        if (body != null) ...[
          const SizedBox(height: AppSpacing.sp2),
          Text(
            body!,
            textAlign: TextAlign.center,
            style: context.texts.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
        for (var i = 0; i < actions.length; i++) ...[
          SizedBox(height: i == 0 ? AppSpacing.sp6 : AppSpacing.sp2),
          actions[i],
        ],
      ],
    );
    if (compact) {
      return mark(
        identifier,
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sp4),
          child: content,
        ),
      );
    }
    return mark(
      identifier,
      Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.sp6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// 목록 불러오기 실패. 가운데 오류 타일 + 제목 + 본문 + "다시 불러오기".
Widget loadFailure(
  String id,
  String title,
  String body,
  VoidCallback retry, {
  String retryLabel = '다시 불러오기',
}) => EmptyState(
  identifier: id,
  icon: Icons.sync_problem,
  title: title,
  body: body,
  error: true,
  actions: [
    mark(
      '$id.retry.button',
      FilledButton.icon(
        onPressed: retry,
        icon: const Icon(Icons.refresh),
        label: Text(retryLabel),
      ),
    ),
  ],
);

/// 날짜 달력 + 오전/오후 + 시·분을 한 번에 고르는 시트.
class LessonDateSheet extends StatefulWidget {
  final DateTime initial;
  const LessonDateSheet({super.key, required this.initial});
  @override
  State<LessonDateSheet> createState() => _LessonDateSheetState();
}

class _LessonDateSheetState extends State<LessonDateSheet> {
  late DateTime day = DateUtils.dateOnly(widget.initial);
  late int hour = widget.initial.hour;
  late int minute = widget.initial.minute;

  /// 시트는 분 단위로 고른다. 아무것도 바꾸지 않으면 초·밀리초까지 원래 값을
  /// 그대로 돌려준다(작성 화면이 변경으로 오인하지 않게).
  DateTime get value {
    final picked = DateTime(day.year, day.month, day.day, hour, minute);
    final o = widget.initial;
    final original = DateTime(o.year, o.month, o.day, o.hour, o.minute);
    return picked == original ? o : picked;
  }

  bool get pm => hour >= 12;
  int get hour12 => hour % 12 == 0 ? 12 : hour % 12;

  Widget _box(String id, Widget child) => mark(
    id,
    Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp3),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        border: Border.all(color: context.colors.outline),
        borderRadius: AppRadius.mdAll,
      ),
      child: DropdownButtonHideUnderline(child: child),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final minutes = {for (var m = 0; m < 60; m += 5) m, minute}.toList()
      ..sort();
    return mark(
      'lessons.dateSheet',
      SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.sp4,
          0,
          AppSpacing.sp4,
          AppSpacing.sp4 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sp3,
              runSpacing: AppSpacing.sp2,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      header: true,
                      child: Text('레슨 일시', style: context.texts.titleLarge),
                    ),
                    Text(
                      '실제 수업 시작 일시',
                      style: context.texts.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                StatusPill(
                  label: lessonDate(value),
                  tone: StatusPillTone.primary,
                  identifier: 'lessons.dateSheet.value',
                ),
              ],
            ),
            const Divider(height: AppSpacing.sp6),
            mark(
              'lessons.dateSheet.calendar',
              // 달력 칸은 높이가 고정이라 큰 글꼴에서 넘친다. 기본 날짜
              // 다이얼로그처럼 1.3배까지만 키운다.
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: CalendarDatePicker(
                  initialDate: day,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  onDateChanged: (d) => setState(() => day = d),
                ),
              ),
            ),
            const Divider(height: AppSpacing.sp6),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: AppSpacing.sp2,
              children: [
                Text('수업 시작 시간', style: context.texts.titleMedium),
                Text(
                  '실제 수업 진행 기준',
                  style: context.texts.labelMedium?.copyWith(
                    color: colors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sp3),
            Wrap(
              spacing: AppSpacing.sp3,
              runSpacing: AppSpacing.sp2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                mark(
                  'lessons.dateSheet.period',
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, label: Text('오전')),
                      ButtonSegment(value: true, label: Text('오후')),
                    ],
                    selected: {pm},
                    onSelectionChanged: (v) =>
                        setState(() => hour = hour % 12 + (v.first ? 12 : 0)),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _box(
                      'lessons.dateSheet.hour',
                      DropdownButton<int>(
                        value: hour12,
                        style: context.numericTexts.titleMedium.copyWith(
                          color: colors.onSurface,
                        ),
                        items: [
                          for (var h = 1; h <= 12; h++)
                            DropdownMenuItem(value: h, child: Text(_two(h))),
                        ],
                        onChanged: (h) =>
                            setState(() => hour = h! % 12 + (pm ? 12 : 0)),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sp1),
                    const Text('시'),
                    const SizedBox(width: AppSpacing.sp2),
                    _box(
                      'lessons.dateSheet.minute',
                      DropdownButton<int>(
                        value: minute,
                        style: context.numericTexts.titleMedium.copyWith(
                          color: colors.onSurface,
                        ),
                        items: [
                          for (final m in minutes)
                            DropdownMenuItem(value: m, child: Text(_two(m))),
                        ],
                        onChanged: (m) => setState(() => minute = m!),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sp1),
                    const Text('분'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sp6),
            Row(
              children: [
                Expanded(
                  child: mark(
                    'lessons.dateSheet.cancel.button',
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('취소'),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sp3),
                Expanded(
                  flex: 2,
                  child: mark(
                    'lessons.dateSheet.apply.button',
                    FilledButton(
                      onPressed: () => Navigator.pop(context, value),
                      child: const Text('적용하기'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 사진 한 장 썸네일(3:4 프레임, 원본 비율 유지) + 아래 방향 라벨.
///
/// [onRemove]가 있으면 오른쪽 위에 제거 버튼(터치 48dp)을 얹는다.
class LessonPhotoThumb extends StatelessWidget {
  final String identifier;
  final String path;
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final String removeTooltip;
  const LessonPhotoThumb({
    super.key,
    required this.identifier,
    required this.path,
    required this.label,
    this.onTap,
    this.onRemove,
    this.removeTooltip = '사진 제거',
  });

  @override
  Widget build(BuildContext context) {
    final frame = AspectRatio(
      aspectRatio: 3 / 4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.photoColors.backdrop,
          borderRadius: AppRadius.smAll,
        ),
        child: ClipRRect(
          borderRadius: AppRadius.smAll,
          child: LayoutBuilder(
            builder: (context, box) => Image.file(
              File(path),
              fit: BoxFit.contain,
              cacheWidth: box.maxWidth.isFinite
                  ? (box.maxWidth * MediaQuery.devicePixelRatioOf(context))
                        .round()
                  : null,
              errorBuilder: (_, _, _) => Icon(
                Icons.broken_image_outlined,
                color: context.photoColors.onChrome,
              ),
            ),
          ),
        ),
      ),
    );
    return mark(
      identifier,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Semantics(
                button: onTap != null,
                label: '$label 사진',
                image: true,
                child: InkWell(
                  borderRadius: AppRadius.smAll,
                  onTap: onTap,
                  child: frame,
                ),
              ),
              if (onRemove != null)
                Positioned(
                  top: -12,
                  right: -12,
                  child: IconButton(
                    key: ValueKey('$identifier.remove.button'),
                    tooltip: removeTooltip,
                    onPressed: onRemove,
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(AppSpacing.minTouchTarget),
                    ),
                    icon: CircleAvatar(
                      radius: 12,
                      backgroundColor: context.photoColors.chrome,
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: context.photoColors.onChrome,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sp1),
          ExcludeSemantics(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// 사진 묶음 머리글 "● 수업 전 (4장 완료)" + 오른쪽 촬영 시각.
Widget photoGroupHeader(
  BuildContext context,
  String phase,
  List<BodyDirection> directions,
  DateTime? at,
) {
  final done = directions.toSet().length >= 4;
  return Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sp3, bottom: AppSpacing.sp2),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sp2,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 8, color: context.colors.primary),
            const SizedBox(width: AppSpacing.sp2),
            Flexible(
              child: Text(
                '${phases[phase] ?? phase} (${directions.length}장${done ? ' 완료' : ''})',
                style: context.texts.labelLarge,
              ),
            ),
          ],
        ),
        if (at != null)
          Text(
            '${clockTime(at)} 촬영',
            style: context.numericTexts.bodySmall.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
      ],
    ),
  );
}

/// 4열 격자. 빈 칸은 자리만 차지해 열 너비를 맞춘다.
Widget photoGrid(List<Widget> tiles) => Column(
  children: [
    for (var row = 0; row < tiles.length; row += 4)
      Padding(
        padding: EdgeInsets.only(top: row == 0 ? 0 : AppSpacing.sp3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = row; i < row + 4; i++) ...[
              if (i > row) const SizedBox(width: AppSpacing.sp2),
              Expanded(
                child: i < tiles.length ? tiles[i] : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ),
  ],
);

class MainNavigation extends StatelessWidget {
  final int index;
  const MainNavigation(this.index, {super.key});
  @override
  Widget build(BuildContext context) => mark(
    'main.navigation',
    NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (i) =>
          context.go(['/', '/records', '/settings'][i]),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: '회원',
        ),
        NavigationDestination(
          icon: Icon(Icons.article_outlined),
          selectedIcon: Icon(Icons.article),
          label: '기록',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: '설정',
        ),
      ],
    ),
  );
}
