import 'package:flutter/material.dart';

/// 문구와 위치에 의존하지 않는 Semantics.identifier + ValueKey를 갖춘 스위치.
class LabeledSwitch extends StatelessWidget {
  final String id;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const LabeledSwitch({
    super.key,
    required this.id,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: id,
      label: title,
      value: value ? '켜짐' : '꺼짐',
      child: SwitchListTile(
        key: ValueKey(id),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
