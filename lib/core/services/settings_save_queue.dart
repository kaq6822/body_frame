import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 설정 영속 저장의 진행 상태.
///
/// 설정 값 상태와 분리한다. 슬라이더를 움직이는 중 저장이 실패해도 미리보기는
/// 마지막 선택값을 유지해야 하고, 그 실패로 화면 전체가 오류 상태로 바뀌어서는
/// 안 된다. 저장은 뒤에서 따라가며 진행·성공·실패만 따로 알린다.
enum SettingsSaveStatus { idle, saving, success, failure }

/// 마지막 저장 요청의 상태.
class SettingsSaveState {
  final SettingsSaveStatus status;

  /// 마지막으로 저장을 시도한 값. 실패했을 때 재시도 대상이 된다.
  final Object? lastAttempted;

  /// 마지막 저장에서 발생한 예외. 원인 예외는 로컬 경로를 담고 있을 수 있어
  /// 화면에 직접 노출하지 않는다.
  final Object? error;

  const SettingsSaveState({
    this.status = SettingsSaveStatus.idle,
    this.lastAttempted,
    this.error,
  });

  const SettingsSaveState.idle() : this(status: SettingsSaveStatus.idle);

  bool get isSaving => status == SettingsSaveStatus.saving;
  bool get isFailure => status == SettingsSaveStatus.failure;

  /// 재시도할 값이 남아 있는가.
  bool get canRetry => isFailure && lastAttempted != null;
}

/// 순서를 보장하는 설정 저장 큐.
///
/// 설정 저장에는 두 가지 위험이 있다. 하나는 **순서**다. 슬라이더를 빠르게 움직이면
/// 저장 호출이 겹치고, 늦게 끝난 옛 요청이 마지막 선택을 덮어쓸 수 있다. 다른
/// 하나는 **중간값 폭주**다. 드래그 중 모든 중간값을 저장하면 불필요한 쓰기가
/// 쌓인다. 이 큐는 저장을 직렬화해 호출 순서를 지키고, 진행 중인 저장이 끝나기
/// 전에 도착한 요청은 **최신 값 하나로 합쳐** 한 번만 저장한다.
///
/// 실패는 예외로 던지지 않고 [state]로 알린다. 슬라이더 콜백처럼 결과를 버리는
/// 호출부에서 미처리 예외가 남으면 그 조작 자체가 실패한 것처럼 보이기 때문이다.
/// 마지막 선택값은 [state]에 남으므로 [retry]로 그대로 다시 저장할 수 있다.
class SettingsSaveQueue<T> extends StateNotifier<SettingsSaveState> {
  /// 실제 영속화를 수행하는 함수. 역순 완료 Fake로 순서 보장을 검증한다.
  final Future<void> Function(T value) _write;

  /// 초기화 동작. 없으면 [resetToDefault]은 아무것도 하지 않는다.
  final Future<void> Function()? _reset;

  /// 저장 중이라 아직 실행되지 않은 요청들(순서 유지).
  final List<_PendingSave<T>> _pending = [];

  /// 마지막으로 요청한 값. 실패 후 [retry]가 다시 쓴다.
  T? _lastRequested;

  bool _draining = false;

  SettingsSaveQueue(this._write, {Future<void> Function()? reset})
    : _reset = reset,
      super(const SettingsSaveState.idle());

  /// [value]를 저장한다.
  ///
  /// 반환 Future는 이 요청의 저장이 끝났거나 실패해 결과가 정해진 시점에 완료된다.
  /// 저장 도중 더 최신 값이 들어오면 그 값이 대신 저장되고 이 요청도 그 결과로
  /// 완료된다(최신 의도가 우선).
  Future<SettingsSaveState> save(T value) {
    final request = _PendingSave<T>(value);
    _pending.add(request);
    _lastRequested = value;
    state = SettingsSaveState(
      status: SettingsSaveStatus.saving,
      lastAttempted: value,
    );
    _startDraining();
    return request.completer.future;
  }

  /// 마지막으로 요청한 값을 다시 저장한다. 실패 후 재시도 경로다.
  Future<SettingsSaveState> retry() {
    final value = _lastRequested;
    if (value == null) return Future<SettingsSaveState>.value(state);
    return save(value);
  }

  /// 저장 기본값으로 되돌린다.
  Future<SettingsSaveState> resetToDefault() {
    final reset = _reset;
    if (reset == null) return Future<SettingsSaveState>.value(state);
    final request = _PendingSave<T>(null, run: reset);
    _pending.add(request);
    state = const SettingsSaveState(status: SettingsSaveStatus.saving);
    _startDraining();
    return request.completer.future;
  }

  void _startDraining() {
    if (_draining) return;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    _draining = true;
    try {
      while (_pending.isNotEmpty) {
        // 진행 중인 저장이 끝날 때까지 쌓인 요청은 최신 값 하나로 합친다.
        // 나머지 요청은 이 저장으로 의도가 반영되므로 결과만 돌려준다.
        final batch = List<_PendingSave<T>>.of(_pending);
        _pending.clear();
        final latest = batch.removeLast();
        final result = await _run(latest);
        // 개별 Future에는 해당 요청의 결과를 반환하되, 화면의 저장 상태는
        // 최신 대기 요청까지 끝나야 성공/실패로 바뀐다.
        if (_pending.isEmpty && mounted) state = result;
        for (final request in [latest, ...batch]) {
          if (!request.completer.isCompleted) {
            request.completer.complete(result);
          }
        }
      }
    } finally {
      _draining = false;
    }
  }

  /// [latest]를 저장해 성공/실패 상태를 만든다. 예외는 밖으로 내보내지 않는다.
  Future<SettingsSaveState> _run(_PendingSave<T> latest) async {
    try {
      await latest.write(_write);
      final success = SettingsSaveState(
        status: SettingsSaveStatus.success,
        lastAttempted: latest.value,
      );
      return success;
    } catch (error) {
      final failure = SettingsSaveState(
        status: SettingsSaveStatus.failure,
        lastAttempted: latest.value,
        error: error,
      );
      return failure;
    }
  }
}

/// 대기 중인 저장 요청 1건.
class _PendingSave<T> {
  /// 저장할 값. 초기화 요청은 null이다.
  final T? value;

  /// 초기화 요청이 직접 수행할 동작.
  final Future<void> Function()? run;

  final Completer<SettingsSaveState> completer = Completer();

  _PendingSave(this.value, {this.run});

  Future<void> write(Future<void> Function(T value) write) async {
    final action = run;
    if (action != null) return action();
    return write(value as T);
  }
}
