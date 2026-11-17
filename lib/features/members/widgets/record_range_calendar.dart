import 'package:flutter/material.dart';
import '../../../core/korean_text.dart';
import '../../../core/theme/app_tokens.dart';
import '../../records/providers/records_providers.dart';
import '../ui.dart';
import 'member_filter_sheet.dart';

/// 기간 시트의 빠른 선택.
enum RecordRangePreset {
  today('today', '오늘'),
  week('week', '이번 주'),
  month('month', '이번 달'),
  lastMonth('lastMonth', '지난 달'),
  threeMonths('3months', '최근 3개월');

  final String id;
  final String label;
  const RecordRangePreset(this.id, this.label);
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _two(int v) => v.toString().padLeft(2, '0');

/// 달력 한 달의 6줄(42칸) 날짜. 일요일부터 시작하고 앞뒤 달 날짜로 채운다.
List<DateTime> monthGridDays(DateTime month) {
  final first = DateTime(month.year, month.month);
  // DateTime.weekday는 월요일=1 … 일요일=7. 일요일 시작 칸 번호로 바꾼다.
  final lead = first.weekday % 7;
  return [
    for (var i = 0; i < 42; i++)
      DateTime(first.year, first.month, 1 - lead + i),
  ];
}

/// 날짜(자정)별 기록 수. 회원 필터 [memberFilter]에 들어가는 기록만 센다.
Map<DateTime, int> recordCountsByDay(
  Iterable<RecordWithPhotos> records,
  String? memberFilter,
) {
  final counts = <DateTime, int>{};
  for (final item in records) {
    if (!matchesMemberFilter(item.record.memberId, memberFilter)) continue;
    final day = _dateOnly(item.record.shotAt);
    counts[day] = (counts[day] ?? 0) + 1;
  }
  return counts;
}

/// [now] 기준 프리셋 기간. 시작·끝 모두 그날 자정이고 끝 날짜를 포함한다.
/// 이번 주는 월요일부터 일요일까지다.
DateTimeRange presetRange(RecordRangePreset preset, DateTime now) {
  final y = now.year;
  final m = now.month;
  final d = now.day;
  switch (preset) {
    case RecordRangePreset.today:
      final today = DateTime(y, m, d);
      return DateTimeRange(start: today, end: today);
    case RecordRangePreset.week:
      final monday = DateTime(y, m, d - (now.weekday - 1));
      return DateTimeRange(
        start: monday,
        end: DateTime(monday.year, monday.month, monday.day + 6),
      );
    case RecordRangePreset.month:
      return DateTimeRange(start: DateTime(y, m), end: DateTime(y, m + 1, 0));
    case RecordRangePreset.lastMonth:
      return DateTimeRange(start: DateTime(y, m - 1), end: DateTime(y, m, 0));
    case RecordRangePreset.threeMonths:
      final base = DateTime(y, m - 3);
      final days = DateUtils.getDaysInMonth(base.year, base.month);
      return DateTimeRange(
        start: DateTime(base.year, base.month, d > days ? days : d),
        end: DateTime(y, m, d),
      );
  }
}

/// [at]이 [range]의 시작일 0시부터 끝 날짜 23:59:59.999까지 안에 드는지.
bool inDayRange(DateTime at, DateTimeRange range) {
  final end = range.end;
  return !at.isBefore(_dateOnly(range.start)) &&
      at.isBefore(DateTime(end.year, end.month, end.day + 1));
}

/// [counts] 가운데 [range] 안 날짜의 기록 수 합.
int countInRange(Map<DateTime, int> counts, DateTimeRange range) {
  var total = 0;
  counts.forEach((day, n) {
    if (inDayRange(day, range)) total += n;
  });
  return total;
}

/// "11.17". [now]와 해가 다르면 "2025.11.17".
String recordDayLabel(DateTime d, DateTime now) => d.year == now.year
    ? '${_two(d.month)}.${_two(d.day)}'
    : '${d.year}.${_two(d.month)}.${_two(d.day)}';

/// "11.03 ~ 11.17". 하루짜리면 날짜 하나만 쓴다.
String recordRangeLabel(DateTimeRange r, DateTime now) =>
    DateUtils.isSameDay(r.start, r.end)
    ? recordDayLabel(r.start, now)
    : '${recordDayLabel(r.start, now)} ~ ${recordDayLabel(r.end, now)}';

/// 기간 시트 결과. [range]가 null이면 전체 기간(초기화)이다.
class RecordRangeChoice {
  final DateTimeRange? range;
  const RecordRangeChoice(this.range);
}

/// 기록 기간 시트. 적용·초기화하면 [RecordRangeChoice], 그냥 닫으면 null.
Future<RecordRangeChoice?> showRecordRangeSheet(
  BuildContext context, {
  required Map<DateTime, int> counts,
  required DateTimeRange? initial,
  required DateTime now,
}) => showModalBottomSheet<RecordRangeChoice>(
  // 탭 틀 안에서 열면 하단 탭 위에 걸쳐 뜬다. 화면 전체를 덮게 연다.
  useRootNavigator: true,
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => RecordRangeSheet(counts: counts, initial: initial, now: now),
);

class RecordRangeSheet extends StatefulWidget {
  /// 날짜(자정)별 기록 수. 현재 회원 필터를 이미 반영한 값이다.
  final Map<DateTime, int> counts;
  final DateTimeRange? initial;
  final DateTime now;
  const RecordRangeSheet({
    super.key,
    required this.counts,
    required this.initial,
    required this.now,
  });

  @override
  State<RecordRangeSheet> createState() => _RecordRangeSheetState();
}

class _RecordRangeSheetState extends State<RecordRangeSheet> {
  late DateTime? start = widget.initial == null
      ? null
      : _dateOnly(widget.initial!.start);
  late DateTime? end = widget.initial == null
      ? null
      : _dateOnly(widget.initial!.end);
  late DateTime month = _initialMonth();

  DateTime _initialMonth() {
    final DateTime base;
    if (widget.initial != null) {
      base = widget.initial!.start;
    } else if (widget.counts.isNotEmpty) {
      base = widget.counts.keys.reduce((a, b) => a.isAfter(b) ? a : b);
    } else {
      base = widget.now;
    }
    return DateTime(base.year, base.month);
  }

  /// 시작일만 골랐으면 그날 하루로 본다.
  DateTimeRange? get draft =>
      start == null ? null : DateTimeRange(start: start!, end: end ?? start!);

  void _tapDay(DateTime d) => setState(() {
    if (start == null || end != null) {
      start = d;
      end = null;
    } else if (d.isBefore(start!)) {
      start = d;
    } else {
      end = d;
    }
  });

  void _preset(RecordRangePreset p) => setState(() {
    final r = presetRange(p, widget.now);
    start = r.start;
    end = r.end;
    month = DateTime(r.start.year, r.start.month);
  });

  void _move(int delta) =>
      setState(() => month = DateTime(month.year, month.month + delta));

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final range = draft;
    final count = range == null ? 0 : countInRange(widget.counts, range);
    return mark(
      'lessons.date.sheet',
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text('기간 선택', style: context.texts.titleLarge),
                  ),
                  const SizedBox(height: AppSpacing.sp3),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final p in RecordRangePreset.values)
                          Padding(
                            padding: const EdgeInsets.only(
                              right: AppSpacing.sp2,
                            ),
                            child: mark(
                              'lessons.date.preset.${p.id}',
                              ChoiceChip(
                                label: Text(p.label),
                                showCheckmark: false,
                                selected:
                                    range != null &&
                                    end != null &&
                                    range == presetRange(p, widget.now),
                                onSelected: (_) => _preset(p),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sp3),
                  // 달력 칸은 높이가 고정이라 큰 글꼴에서 넘친다. 레슨 일시
                  // 달력처럼 1.3배까지만 키운다.
                  MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: RecordRangeCalendar(
                      month: month,
                      counts: widget.counts,
                      start: start,
                      end: end,
                      today: _dateOnly(widget.now),
                      onDayTap: _tapDay,
                      onMonthMove: _move,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sp3),
                  mark(
                    'lessons.date.sheet.summary',
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        range == null
                            ? keepPhrasesWhole('시작일을 골라주세요')
                            : '${recordRangeLabel(range, widget.now)} · 기록 $count개',
                        style: context.numericTexts.bodyMedium.copyWith(
                          color: range == null
                              ? colors.onSurfaceVariant
                              : colors.onSurface,
                          fontWeight: range == null ? null : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sp4,
                AppSpacing.sp3,
                AppSpacing.sp4,
                AppSpacing.sp4,
              ),
              child: Row(
                children: [
                  mark(
                    'lessons.date.sheet.clear',
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(context, const RecordRangeChoice(null)),
                      child: const Text('초기화'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sp3),
                  Expanded(
                    child: mark(
                      'lessons.date.sheet.apply',
                      FilledButton(
                        onPressed: range == null
                            ? null
                            : () => Navigator.pop(
                                context,
                                RecordRangeChoice(range),
                              ),
                        child: Text(
                          range == null ? '적용' : '기록 $count개 보기',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 기록이 있는 날에 점을 찍는 기간 선택 달력. 일요일부터 시작한다.
///
/// 칸을 눌러 시작일·끝 날짜를 고르고, 위 화살표나 좌우로 밀어 달을 옮긴다.
class RecordRangeCalendar extends StatelessWidget {
  static const _weekdays = ['일', '월', '화', '수', '목', '금', '토'];
  static const _cellHeight = 44.0;
  static const _circle = 38.0;

  final DateTime month;
  final Map<DateTime, int> counts;
  final DateTime? start;
  final DateTime? end;
  final DateTime today;
  final ValueChanged<DateTime> onDayTap;
  final ValueChanged<int> onMonthMove;

  const RecordRangeCalendar({
    super.key,
    required this.month,
    required this.counts,
    required this.start,
    required this.end,
    required this.today,
    required this.onDayTap,
    required this.onMonthMove,
  });

  static String dayId(DateTime d) =>
      'lessons.date.day.${d.year}${_two(d.month)}${_two(d.day)}';

  Widget _cell(BuildContext context, DateTime d) {
    if (d.month != month.month) return const SizedBox(height: _cellHeight);
    final colors = context.colors;
    final count = counts[d] ?? 0;
    final isStart = start != null && d == start;
    final isEnd = end != null && d == end;
    final endpoint = isStart || isEnd;
    final spans = start != null && end != null && end != start;
    final inside = spans && d.isAfter(start!) && d.isBefore(end!);
    final bandLeft = inside || (spans && isEnd);
    final bandRight = inside || (spans && isStart);
    final isToday = d == today;
    final textColor = endpoint
        ? colors.onPrimary
        : inside
        ? colors.onPrimaryContainer
        : colors.onSurface;
    final label = [
      '${d.month}월 ${d.day}일',
      count == 0 ? '기록 없음' : '기록 $count개',
      if (isToday) '오늘',
      if (isStart) '시작일',
      if (isEnd && !isStart) '종료일',
      if (inside) '선택 기간',
    ].join(', ');
    final id = dayId(d);
    // primaryContainer는 흰 바탕에서 거의 보이지 않아 기간이 끊겨 보인다.
    final band = colors.primary.withValues(alpha: 0.16);
    return Semantics(
      identifier: id,
      button: true,
      selected: endpoint || inside,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        key: ValueKey(id),
        onTap: () => onDayTap(d),
        radius: _circle / 2,
        child: SizedBox(
          height: _cellHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 0,
                right: 0,
                height: _circle,
                // 자식 없는 ColoredBox는 높이가 0이 되므로 세로로 늘린다.
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ColoredBox(
                        color: bandLeft ? band : Colors.transparent,
                      ),
                    ),
                    Expanded(
                      child: ColoredBox(
                        color: bandRight ? band : Colors.transparent,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: _circle,
                height: _circle,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: endpoint ? colors.primary : null,
                  border: isToday && !endpoint
                      ? Border.all(color: colors.primary)
                      : null,
                ),
                // 큰 글꼴에서 두 자리 숫자가 원 너비를 넘으면 줄바꿈 대신 줄인다.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${d.day}',
                        maxLines: 1,
                        style: context.numericTexts.bodyMedium.copyWith(
                          color: textColor,
                          height: 1.2,
                          fontWeight: endpoint || isToday
                              ? FontWeight.w700
                              : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        key: count > 0 ? ValueKey('$id.dot') : null,
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: count == 0
                              ? Colors.transparent
                              : endpoint
                              ? colors.onPrimary
                              : colors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final days = monthGridDays(month);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  '${month.year}년 ${month.month}월',
                  key: const ValueKey('lessons.date.month.label'),
                  style: context.texts.titleMedium,
                ),
              ),
            ),
            mark(
              'lessons.date.month.prev',
              IconButton(
                tooltip: '이전 달',
                onPressed: () => onMonthMove(-1),
                icon: const Icon(Icons.chevron_left),
              ),
            ),
            mark(
              'lessons.date.month.next',
              IconButton(
                tooltip: '다음 달',
                onPressed: () => onMonthMove(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sp2),
        ExcludeSemantics(
          child: Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: Text(
                    _weekdays[c],
                    textAlign: TextAlign.center,
                    style: context.texts.labelMedium?.copyWith(
                      color: c == 0
                          ? colors.error.withValues(alpha: 0.8)
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sp1),
        GestureDetector(
          key: const ValueKey('lessons.date.grid'),
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (details) {
            final v = details.primaryVelocity ?? 0;
            if (v < -200) onMonthMove(1);
            if (v > 200) onMonthMove(-1);
          },
          child: Column(
            children: [
              for (var r = 0; r < 6; r++)
                Row(
                  children: [
                    for (var c = 0; c < 7; c++)
                      Expanded(child: _cell(context, days[r * 7 + c])),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
