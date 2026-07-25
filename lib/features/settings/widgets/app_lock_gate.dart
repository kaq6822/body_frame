import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../providers/settings_providers.dart';

/// 앱 잠금 게이트. `MaterialApp.router`의 `builder`에 삽입해 전체 화면을 감싼다.
///
/// - 앱이 백그라운드로 이동하면 최근 앱 화면에서 콘텐츠를 가린다.
/// - 자동 잠금 시간이 지나면 재인증을 요구한다.
/// - 최초 실행(콜드 스타트) 시 잠금 방식이 설정돼 있으면 인증을 요구한다.
class AppLockGate extends ConsumerStatefulWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  bool _locked = false;
  bool _hiddenInBackground = false;
  bool _coldStartChecked = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final settings = ref.read(appSettingsControllerProvider).valueOrNull;
    final lockEnabled = settings != null && settings.lockMode != LockMode.none;

    final backgroundStates = {
      AppLifecycleState.paused,
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
    };

    if (backgroundStates.contains(state)) {
      _backgroundedAt = DateTime.now();
      // 잠금을 사용하지 않더라도 최근 앱 미리보기에는 민감한 사진과 회원
      // 정보가 노출되지 않도록 항상 보호 화면으로 덮는다.
      setState(() => _hiddenInBackground = true);
      return;
    }

    if (state == AppLifecycleState.resumed) {
      final bgAt = _backgroundedAt;
      _backgroundedAt = null;
      if (lockEnabled && bgAt != null) {
        final elapsed = DateTime.now().difference(bgAt).inSeconds;
        final autoLockSeconds = settings.autoLockSeconds;
        if (autoLockSeconds > 0 && elapsed >= autoLockSeconds) {
          setState(() {
            _locked = true;
            _hiddenInBackground = false;
          });
          return;
        }
      }
      setState(() => _hiddenInBackground = false);
    }
  }

  void _checkColdStart(AppSettings settings) {
    if (_coldStartChecked) return;
    _coldStartChecked = true;
    if (settings.lockMode != LockMode.none) {
      _locked = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsControllerProvider);

    return settingsAsync.when(
      data: (settings) {
        _checkColdStart(settings);
        final contentCovered = _hiddenInBackground || _locked;
        return Stack(
          children: [
            ExcludeSemantics(excluding: contentCovered, child: widget.child),
            if (_hiddenInBackground) const _BackgroundCoverOverlay(),
            if (_locked)
              _LockScreen(
                settings: settings,
                onUnlocked: () => setState(() => _locked = false),
              ),
          ],
        );
      },
      // 잠금 설정을 아직 알 수 없는 동안에는 콘텐츠를 가린다(fail-safe).
      // 잠금을 설정한 사용자의 콜드 스타트에서 민감한 화면이 잠금 화면보다
      // 먼저 렌더링되는 노출 창을 막는다.
      loading: () => Stack(
        children: [
          ExcludeSemantics(child: widget.child),
          const _BackgroundCoverOverlay(),
        ],
      ),
      // 설정 저장소 접근 자체가 실패하면 잠금 사용 여부를 확인할 수 없으므로
      // 민감한 본문을 노출하지 않고 재시도 가능한 보호 화면을 표시한다.
      error: (e, st) => Stack(
        children: [
          ExcludeSemantics(child: widget.child),
          _SettingsFailureOverlay(
            onRetry: () => ref.invalidate(appSettingsControllerProvider),
          ),
        ],
      ),
    );
  }
}

class _BackgroundCoverOverlay extends StatelessWidget {
  const _BackgroundCoverOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Semantics(
        key: const ValueKey('screen.lock.backgroundCover'),
        identifier: 'screen.lock.backgroundCover',
        container: true,
        label: '화면 보호 중',
        child: Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: const Center(child: Icon(Icons.lock, size: 48)),
        ),
      ),
    );
  }
}

class _SettingsFailureOverlay extends StatelessWidget {
  final VoidCallback onRetry;

  const _SettingsFailureOverlay({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Semantics(
        identifier: 'screen.lock.settingsError',
        container: true,
        label: '잠금 설정을 불러오지 못함',
        child: Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock, size: 48),
                const SizedBox(height: 16),
                const Text('잠금 설정을 불러오지 못했습니다'),
                const SizedBox(height: 8),
                FilledButton(
                  key: const ValueKey('lock.settings.retry.button'),
                  onPressed: onRetry,
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

class _LockScreen extends ConsumerStatefulWidget {
  final AppSettings settings;
  final VoidCallback onUnlocked;

  const _LockScreen({required this.settings, required this.onUnlocked});

  @override
  ConsumerState<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<_LockScreen> {
  static const screenId = 'screen.lock.gate';

  final _secretController = TextEditingController();
  String? _error;
  bool _busy = false;
  DateTime? _lockedUntil;
  Timer? _lockoutTicker;

  bool get _isLockedOut =>
      _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);

  int get _lockoutRemainingSeconds =>
      _isLockedOut ? _lockedUntil!.difference(DateTime.now()).inSeconds + 1 : 0;

  bool get _biometricOnly => widget.settings.lockMode == LockMode.biometric;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadThrottle());
    if (widget.settings.biometricEnabled || _biometricOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
    }
  }

  @override
  void dispose() {
    _lockoutTicker?.cancel();
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _loadThrottle() async {
    final state = await ref.read(lockServiceProvider).loadThrottleState();
    if (!mounted) return;
    _lockedUntil = state.lockedUntil;
    if (state.isLockedOut) {
      _startLockoutTicker();
      setState(() {});
    }
  }

  void _startLockoutTicker() {
    _lockoutTicker?.cancel();
    // 남은 제한 시간 표시를 1초마다 갱신하고, 제한이 끝나면 자동 해제한다.
    _lockoutTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (!_isLockedOut) {
        t.cancel();
        setState(() {
          _lockedUntil = null;
          _error = null;
        });
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _submitSecret() async {
    if (_isLockedOut) return;
    final secret = _secretController.text;
    if (secret.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref.read(lockServiceProvider).verifySecret(secret);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _secretController.clear();
      widget.onUnlocked();
    } else {
      final throttle = await ref.read(lockServiceProvider).loadThrottleState();
      if (!mounted) return;
      if (throttle.isLockedOut) {
        _lockedUntil = throttle.lockedUntil;
        _startLockoutTicker();
        setState(() {});
      } else {
        setState(() => _error = '일치하지 않습니다. 다시 시도해 주세요.');
      }
    }
  }

  Future<void> _tryBiometric() async {
    final lock = ref.read(lockServiceProvider);
    if (!await lock.isBiometricAvailable()) return;
    final ok = await lock.authenticateWithBiometrics();
    if (ok && mounted) widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    final isPassword = widget.settings.lockMode == LockMode.password;
    final label = isPassword ? '비밀번호 입력' : 'PIN 입력';

    return Positioned.fill(
      child: Semantics(
        identifier: screenId,
        container: true,
        label: '앱 잠금 화면',
        child: Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock, size: 48),
                    const SizedBox(height: 16),
                    const Text('잠금 해제', style: TextStyle(fontSize: 20)),
                    const SizedBox(height: 24),
                    // 생체 인증 전용 모드에서는 저장된 비밀번호/PIN이 없으므로
                    // 입력 필드를 노출하지 않는다(혼란 방지).
                    if (!_biometricOnly) ...[
                      SizedBox(
                        width: 220,
                        child: TextField(
                          key: const ValueKey('lock.gate.secret.field'),
                          controller: _secretController,
                          enabled: !_isLockedOut,
                          obscureText: true,
                          keyboardType: isPassword
                              ? TextInputType.visiblePassword
                              : TextInputType.number,
                          autocorrect: false,
                          enableSuggestions: false,
                          maxLength: isPassword ? 128 : 12,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            labelText: label,
                            counterText: '',
                          ),
                          onSubmitted: (_) => _submitSecret(),
                        ),
                      ),
                      if (_isLockedOut) ...[
                        const SizedBox(height: 8),
                        Text(
                          '시도 횟수를 초과했습니다. $_lockoutRemainingSeconds초 후 '
                          '다시 시도해 주세요.',
                          key: const ValueKey('lock.gate.lockout.text'),
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      ] else if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          key: const ValueKey('lock.gate.error.text'),
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                      const SizedBox(height: 16),
                      ElevatedButton(
                        key: const ValueKey('lock.gate.submit.button'),
                        onPressed: (_busy || _isLockedOut)
                            ? null
                            : _submitSecret,
                        child: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('확인'),
                      ),
                    ],
                    if (widget.settings.biometricEnabled || _biometricOnly) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        key: const ValueKey('lock.gate.biometric.button'),
                        onPressed: _tryBiometric,
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('생체 인증으로 잠금 해제'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
