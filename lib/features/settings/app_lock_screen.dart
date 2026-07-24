import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import 'providers/settings_providers.dart';

/// 17. 앱 잠금 설정 화면. MVP.md 11장.
///
/// 잠금 방식(없음/비밀번호/PIN/생체 인증) 선택, PIN 설정·변경·해제, 생체 인증
/// 사용 토글, 자동 잠금 시간 설정을 제공한다.
class AppLockScreen extends ConsumerWidget {
  static const screenId = 'screen.settings.lock';

  const AppLockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsControllerProvider);

    return Semantics(
      identifier: screenId,
      container: true,
      label: '앱 잠금 설정',
      child: Scaffold(
        key: const ValueKey(screenId),
        appBar: AppBar(title: const Text('앱 잠금 설정')),
        body: settingsAsync.when(
          data: (settings) => _AppLockBody(settings: settings),
          loading: () => const Center(
            key: ValueKey('screen.settings.lock.status'),
            child: CircularProgressIndicator(),
          ),
          error: (e, st) => Center(
            key: const ValueKey('screen.settings.lock.status'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('설정을 불러오지 못했습니다'),
                const SizedBox(height: 8),
                ElevatedButton(
                  key: const ValueKey('lock.retry.button'),
                  onPressed: () => ref.invalidate(appSettingsControllerProvider),
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const List<int> _autoLockOptions = [0, 15, 30, 60, 300];

String _autoLockLabel(int seconds) {
  if (seconds <= 0) return '사용 안 함';
  if (seconds < 60) return '$seconds초';
  return '${seconds ~/ 60}분';
}

class _AppLockBody extends ConsumerStatefulWidget {
  final AppSettings settings;

  const _AppLockBody({required this.settings});

  @override
  ConsumerState<_AppLockBody> createState() => _AppLockBodyState();
}

class _AppLockBodyState extends ConsumerState<_AppLockBody> {
  bool? _hasSecret;
  bool _biometricAvailable = false;
  bool _busy = false;
  String? _statusMessage;
  bool _statusIsError = false;

  final _newSecretController = TextEditingController();
  final _confirmSecretController = TextEditingController();
  final _currentSecretController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refreshSecretState();
    _checkBiometricAvailability();
  }

  @override
  void dispose() {
    _newSecretController.dispose();
    _confirmSecretController.dispose();
    _currentSecretController.dispose();
    super.dispose();
  }

  Future<void> _refreshSecretState() async {
    final has = await ref.read(lockServiceProvider).hasSecret();
    if (!mounted) return;
    setState(() => _hasSecret = has);
  }

  Future<void> _checkBiometricAvailability() async {
    final available = await ref.read(lockServiceProvider).isBiometricAvailable();
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
  }

  void _setStatus(String message, {bool isError = false}) {
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
    });
  }

  Future<void> _selectMode(LockMode mode) async {
    if (mode == LockMode.none) {
      await ref
          .read(appSettingsControllerProvider.notifier)
          .updateSettings((s) => s.copyWith(lockMode: LockMode.none, biometricEnabled: false));
      _setStatus('잠금을 사용하지 않습니다');
      return;
    }
    if (mode == LockMode.biometric) {
      if (!_biometricAvailable) {
        _setStatus('이 기기에서 생체 인증을 사용할 수 없습니다', isError: true);
        return;
      }
      await ref
          .read(appSettingsControllerProvider.notifier)
          .updateSettings((s) => s.copyWith(lockMode: LockMode.biometric, biometricEnabled: true));
      _setStatus('생체 인증 잠금을 사용합니다');
      return;
    }
    // password/pin: 아직 비밀이 없으면 설정 폼을 통해 완료해야 실제로 적용된다.
    if (_hasSecret == true) {
      await ref
          .read(appSettingsControllerProvider.notifier)
          .updateSettings((s) => s.copyWith(lockMode: mode));
      _setStatus('${mode.label} 잠금을 사용합니다');
    } else {
      setState(() {}); // 아래 PIN 설정 폼이 보이도록 리렌더만 유도.
    }
  }

  Future<void> _submitNewSecret(LockMode mode) async {
    final next = _newSecretController.text;
    final confirm = _confirmSecretController.text;
    if (next.length < 4) {
      _setStatus('4자 이상 입력해 주세요', isError: true);
      return;
    }
    if (next != confirm) {
      _setStatus('입력한 값이 서로 일치하지 않습니다', isError: true);
      return;
    }
    setState(() => _busy = true);
    await ref.read(lockServiceProvider).setSecret(next);
    await ref
        .read(appSettingsControllerProvider.notifier)
        .updateSettings((s) => s.copyWith(lockMode: mode));
    _newSecretController.clear();
    _confirmSecretController.clear();
    _currentSecretController.clear();
    if (!mounted) return;
    setState(() => _busy = false);
    await _refreshSecretState();
    _setStatus('${mode.label}이 설정되었습니다');
  }

  Future<void> _changeSecret(LockMode mode) async {
    final current = _currentSecretController.text;
    final next = _newSecretController.text;
    final confirm = _confirmSecretController.text;
    final ok = await ref.read(lockServiceProvider).verifySecret(current);
    if (!ok) {
      _setStatus('현재 값이 일치하지 않습니다', isError: true);
      return;
    }
    if (next.length < 4 || next != confirm) {
      _setStatus('새 값을 4자 이상 정확히 입력해 주세요', isError: true);
      return;
    }
    setState(() => _busy = true);
    await ref.read(lockServiceProvider).setSecret(next);
    _currentSecretController.clear();
    _newSecretController.clear();
    _confirmSecretController.clear();
    if (!mounted) return;
    setState(() => _busy = false);
    _setStatus('변경되었습니다');
  }

  Future<void> _clearSecret() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('잠금 해제'),
        content: const Text('설정된 PIN/비밀번호를 삭제하고 앱 잠금을 사용하지 않도록 변경합니다. 계속하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey('lock.pin.clear.confirm.button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(lockServiceProvider).clearSecret();
    await ref
        .read(appSettingsControllerProvider.notifier)
        .updateSettings((s) => s.copyWith(lockMode: LockMode.none, biometricEnabled: false));
    await _refreshSecretState();
    _setStatus('잠금이 해제되었습니다');
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value && !_biometricAvailable) {
      _setStatus('이 기기에서 생체 인증을 사용할 수 없습니다', isError: true);
      return;
    }
    await ref
        .read(appSettingsControllerProvider.notifier)
        .updateSettings((s) => s.copyWith(biometricEnabled: value));
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final needsSecretSetup =
        (settings.lockMode == LockMode.pin || settings.lockMode == LockMode.password) &&
            _hasSecret == false;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('잠금 방식', style: TextStyle(fontWeight: FontWeight.bold)),
        _SelectableModeTile(
          keyValue: 'lock.mode.none.radio',
          label: LockMode.none.label,
          selected: settings.lockMode == LockMode.none,
          onTap: () => _selectMode(LockMode.none),
        ),
        _SelectableModeTile(
          keyValue: 'lock.mode.pin.radio',
          label: LockMode.pin.label,
          selected: settings.lockMode == LockMode.pin,
          onTap: () => _selectMode(LockMode.pin),
        ),
        _SelectableModeTile(
          keyValue: 'lock.mode.password.radio',
          label: LockMode.password.label,
          selected: settings.lockMode == LockMode.password,
          onTap: () => _selectMode(LockMode.password),
        ),
        _SelectableModeTile(
          keyValue: 'lock.mode.biometric.radio',
          label: _biometricAvailable
              ? LockMode.biometric.label
              : '${LockMode.biometric.label} (기기 미지원)',
          selected: settings.lockMode == LockMode.biometric,
          onTap: _biometricAvailable ? () => _selectMode(LockMode.biometric) : null,
        ),
        const Divider(height: 24),
        if (settings.lockMode == LockMode.pin || settings.lockMode == LockMode.password) ...[
          Text(
            needsSecretSetup
                ? '${settings.lockMode.label} 설정'
                : '${settings.lockMode.label} 변경',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (!needsSecretSetup)
            TextField(
              key: const ValueKey('lock.pin.current.field'),
              controller: _currentSecretController,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '현재 값'),
            ),
          TextField(
            key: const ValueKey('lock.pin.field'),
            controller: _newSecretController,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '새 값(4자 이상)'),
          ),
          TextField(
            key: const ValueKey('lock.pin.confirm.field'),
            controller: _confirmSecretController,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '새 값 확인'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const ValueKey('lock.pin.save.button'),
            onPressed: _busy
                ? null
                : () => needsSecretSetup
                    ? _submitNewSecret(settings.lockMode)
                    : _changeSecret(settings.lockMode),
            child: _busy
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(needsSecretSetup ? '설정' : '변경'),
          ),
          if (_hasSecret == true) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('lock.pin.clear.button'),
              onPressed: _clearSecret,
              child: const Text('PIN/비밀번호 삭제(잠금 해제)'),
            ),
          ],
          const Divider(height: 24),
        ],
        SwitchListTile(
          key: const ValueKey('lock.biometric.toggle'),
          title: const Text('생체 인증 사용'),
          subtitle: Text(_biometricAvailable ? '지문/얼굴 인식으로 잠금을 해제합니다' : '이 기기에서 사용할 수 없습니다'),
          value: settings.biometricEnabled,
          onChanged: _biometricAvailable ? _toggleBiometric : null,
        ),
        const Divider(height: 24),
        const Text('자동 잠금 시간', style: TextStyle(fontWeight: FontWeight.bold)),
        DropdownButton<int>(
          key: const ValueKey('lock.autoLock.dropdown'),
          value: settings.autoLockSeconds,
          items: _autoLockOptions
              .map((s) => DropdownMenuItem(value: s, child: Text(_autoLockLabel(s))))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            ref
                .read(appSettingsControllerProvider.notifier)
                .updateSettings((s) => s.copyWith(autoLockSeconds: v));
          },
        ),
        if (_statusMessage != null) ...[
          const SizedBox(height: 16),
          Text(
            _statusMessage!,
            key: const ValueKey('screen.settings.lock.status'),
            style: TextStyle(color: _statusIsError ? Colors.red : Colors.green),
          ),
        ],
      ],
    );
  }
}

/// 잠금 방식 선택 항목. `RadioListTile`의 `groupValue`/`onChanged`가 최근
/// Flutter SDK에서 deprecated 처리되어(`RadioGroup` 권장), 대신 일반
/// `ListTile` + 선택 아이콘으로 동일한 라디오 선택 UX를 구현한다.
class _SelectableModeTile extends StatelessWidget {
  final String keyValue;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _SelectableModeTile({
    required this.keyValue,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: keyValue,
      label: label,
      selected: selected,
      enabled: onTap != null,
      button: true,
      child: ListTile(
        key: ValueKey(keyValue),
        enabled: onTap != null,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: onTap == null ? Theme.of(context).disabledColor : null,
        ),
        title: Text(label),
        onTap: onTap,
      ),
    );
  }
}
