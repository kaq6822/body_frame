import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/services/app_logger.dart';
import '../providers/members_providers.dart';

/// 회원 등록/수정 공용 폼. 이름만 필수이고 나머지는 선택 입력이다.
///
/// [existing]이 null이면 등록, 아니면 해당 회원 정보로 초기화된 수정 폼이다.
/// 호출부(등록/수정 화면)가 각자의 `screen.members.add`/`screen.members.edit`
/// Semantics.identifier를 유지하고, 이 위젯은 `member.*`/`members.save.button`
/// 요소 식별자를 제공한다.
class MemberFormBody extends ConsumerStatefulWidget {
  final Member? existing;

  const MemberFormBody({super.key, this.existing});

  @override
  ConsumerState<MemberFormBody> createState() => _MemberFormBodyState();
}

class _MemberFormBodyState extends ConsumerState<MemberFormBody> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _birthCtrl;
  late final TextEditingController _contactCtrl;
  late final TextEditingController _memoCtrl;
  Gender _gender = Gender.unspecified;

  /// 새로 선택한 갤러리 원본 경로(아직 저장소에 복사되기 전).
  String? _avatarPickedPath;

  /// 수정 시 기존에 저장된 대표 사진 경로.
  String? _avatarExistingPath;
  bool _avatarCleared = false;

  /// 대기(null)/진행(loading)/성공(data)/실패(error) 4-상태.
  AsyncValue<void>? _saveState;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    _nameCtrl = TextEditingController(text: m?.name ?? '');
    _birthCtrl = TextEditingController(text: m?.birth ?? '');
    _contactCtrl = TextEditingController(text: m?.contact ?? '');
    _memoCtrl = TextEditingController(text: m?.memo ?? '');
    _gender = m?.gender ?? Gender.unspecified;
    _avatarExistingPath = m?.avatarPath;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _birthCtrl.dispose();
    _contactCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  String? get _avatarPreviewPath =>
      _avatarCleared ? null : (_avatarPickedPath ?? _avatarExistingPath);

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() {
      _avatarPickedPath = picked.path;
      _avatarCleared = false;
    });
  }

  void _clearAvatar() {
    setState(() {
      _avatarPickedPath = null;
      _avatarCleared = true;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final logger = ref.read(appLoggerProvider);
    final repo = ref.read(memberRepositoryProvider);
    final storage = ref.read(photoStorageServiceProvider);
    final now = DateTime.now();
    final id = widget.existing?.id ?? const Uuid().v4();

    setState(() => _saveState = const AsyncValue.loading());
    logger.phase(
      _isEdit ? 'member.update' : 'member.insert',
      LogPhase.start,
      context: {'id': id},
    );

    try {
      String? avatarPath = _avatarCleared ? null : _avatarExistingPath;
      if (_avatarPickedPath != null) {
        avatarPath = await storage.saveOriginal(
          memberId: id,
          sourcePath: _avatarPickedPath!,
        );
      }

      final member = Member(
        id: id,
        name: _nameCtrl.text.trim(),
        avatarPath: avatarPath,
        gender: _gender,
        birth: _birthCtrl.text.trim().isEmpty ? null : _birthCtrl.text.trim(),
        contact:
            _contactCtrl.text.trim().isEmpty ? null : _contactCtrl.text.trim(),
        memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
        createdAt: widget.existing?.createdAt ?? now,
        updatedAt: now,
      );

      if (_isEdit) {
        await repo.update(member);
      } else {
        await repo.insert(member);
      }
      logger.phase(
        _isEdit ? 'member.update' : 'member.insert',
        LogPhase.success,
        context: {'id': id},
      );

      ref.invalidate(membersListProvider);
      if (_isEdit) {
        ref.invalidate(memberDetailProvider(id));
      }

      if (!mounted) return;
      setState(() => _saveState = const AsyncValue.data(null));
      Navigator.of(context).pop(true);
    } catch (e, st) {
      logger.error(
        _isEdit ? 'member.update.failure' : 'member.insert.failure',
        err: e,
        stack: st,
      );
      if (!mounted) return;
      setState(() => _saveState = AsyncValue.error(e, st));
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusId =
        _isEdit ? 'screen.members.edit.status' : 'screen.members.add.status';
    final saving = _saveState is AsyncLoading;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Column(
                children: [
                  Semantics(
                    identifier: 'member.avatar.image',
                    label: '대표 사진',
                    image: true,
                    child: CircleAvatar(
                      key: const ValueKey('member.avatar.image'),
                      radius: 44,
                      backgroundImage: _avatarPreviewPath != null
                          ? FileImage(File(_avatarPreviewPath!))
                          : null,
                      child: _avatarPreviewPath == null
                          ? const Icon(Icons.person, size: 40)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        identifier: 'member.avatar.button',
                        button: true,
                        enabled: !saving,
                        label: '대표 사진 선택',
                        child: TextButton(
                          key: const ValueKey('member.avatar.button'),
                          onPressed: saving ? null : _pickAvatar,
                          child: const Text('사진 선택'),
                        ),
                      ),
                      if (_avatarPreviewPath != null)
                        Semantics(
                          identifier: 'member.avatar.clear.button',
                          button: true,
                          enabled: !saving,
                          label: '대표 사진 삭제',
                          child: TextButton(
                            key: const ValueKey('member.avatar.clear.button'),
                            onPressed: saving ? null : _clearAvatar,
                            child: const Text('삭제'),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Semantics(
              identifier: 'member.name.field',
              textField: true,
              label: '이름 또는 별칭',
              child: TextFormField(
                key: const ValueKey('member.name.field'),
                controller: _nameCtrl,
                enabled: !saving,
                decoration: const InputDecoration(labelText: '이름 또는 별칭 *'),
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '이름을 입력하세요' : null,
              ),
            ),
            const SizedBox(height: 12),
            Text('성별', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Semantics(
              identifier: 'member.gender.field',
              label: '성별 선택',
              child: Wrap(
                spacing: 8,
                children: Gender.values.map((g) {
                  final selected = _gender == g;
                  return Semantics(
                    identifier: 'member.gender.option.${g.key}',
                    button: true,
                    selected: selected,
                    label: g.label,
                    child: ChoiceChip(
                      key: ValueKey('member.gender.option.${g.key}'),
                      label: Text(g.label),
                      selected: selected,
                      onSelected:
                          saving ? null : (_) => setState(() => _gender = g),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              identifier: 'member.birth.field',
              textField: true,
              label: '생년 또는 연령대',
              child: TextFormField(
                key: const ValueKey('member.birth.field'),
                controller: _birthCtrl,
                enabled: !saving,
                decoration: const InputDecoration(labelText: '생년 또는 연령대'),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              identifier: 'member.contact.field',
              textField: true,
              label: '연락처',
              child: TextFormField(
                key: const ValueKey('member.contact.field'),
                controller: _contactCtrl,
                enabled: !saving,
                decoration: const InputDecoration(labelText: '연락처'),
                keyboardType: TextInputType.phone,
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              identifier: 'member.memo.field',
              textField: true,
              multiline: true,
              label: '메모',
              child: TextFormField(
                key: const ValueKey('member.memo.field'),
                controller: _memoCtrl,
                enabled: !saving,
                decoration: const InputDecoration(labelText: '메모'),
                maxLines: 3,
              ),
            ),
            const SizedBox(height: 20),
            if (_saveState != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Semantics(
                  identifier: statusId,
                  liveRegion: true,
                  label: _statusLabel(_saveState!),
                  child: KeyedSubtree(
                    key: ValueKey(statusId),
                    child: _statusContent(_saveState!),
                  ),
                ),
              ),
            Semantics(
              identifier: 'members.save.button',
              button: true,
              enabled: !saving,
              label: _isEdit ? '수정 내용 저장' : '회원 등록',
              child: FilledButton(
                key: const ValueKey('members.save.button'),
                onPressed: saving ? null : _submit,
                child: Text(_isEdit ? '수정 완료' : '등록'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(AsyncValue<void> s) => s.when(
        data: (_) => '저장 완료',
        loading: () => '저장 중',
        error: (e, _) => '저장 실패: $e',
      );

  Widget _statusContent(AsyncValue<void> s) => s.when(
        data: (_) => const SizedBox.shrink(),
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(),
        ),
        error: (e, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '저장하지 못했습니다: $e',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 4),
            TextButton(onPressed: _submit, child: const Text('다시 시도')),
          ],
        ),
      );
}
