import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

String lessonDate(DateTime d) =>
    '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')} ${d.hour < 12 ? '오전' : '오후'} ${d.hour % 12 == 0 ? 12 : d.hour % 12}:${d.minute.toString().padLeft(2, '0')}';
const phases = {'before': '수업 전', 'after': '수업 후', 'regular': '정기'};
Widget mark(String id, Widget child) => Semantics(
  identifier: id,
  container: true,
  child: KeyedSubtree(key: ValueKey(id), child: child),
);
Widget panel({required Widget child}) => Card(
  margin: const EdgeInsets.only(bottom: 16),
  child: Padding(padding: const EdgeInsets.all(20), child: child),
);
Widget section(String title, Widget child) => panel(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
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
Future<bool> confirm(
  BuildContext context,
  String title,
  String body, {
  String button = '삭제',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        key: const ValueKey('common.confirm.dialog'),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            key: const ValueKey('common.confirm.cancel.button'),
            onPressed: () => Navigator.pop(c, false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey('common.confirm.accept.button'),
            onPressed: () => Navigator.pop(c, true),
            child: Text(button),
          ),
        ],
      ),
    ) ??
    false;
Future<DateTime?> pickLessonDate(BuildContext context, DateTime current) async {
  final day = await showDatePicker(
    context: context,
    initialDate: current,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  if (day == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(current),
  );
  if (time == null) return null;
  return DateTime(day.year, day.month, day.day, time.hour, time.minute);
}

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
