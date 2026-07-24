import 'package:flutter/material.dart';

/// 비동기 작업의 대기/진행/성공/실패를 구분한다.
enum AsyncStatus { idle, busy, success, failure }

/// 공용 4-상태 표시 위젯. [statusId]로 화면별 `screen.<x>.status` 식별자를
/// 부여하고, 실패 시 [onRetry]로 재시도 액션을 노출한다.
class AsyncStatusIndicator extends StatelessWidget {
  final String statusId;
  final AsyncStatus status;
  final String busyLabel;
  final String? failureMessage;
  final String? successLabel;
  final VoidCallback? onRetry;

  const AsyncStatusIndicator({
    super.key,
    required this.statusId,
    required this.status,
    this.busyLabel = '처리 중입니다.',
    this.failureMessage,
    this.successLabel,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final Widget content = switch (status) {
      AsyncStatus.idle => const SizedBox.shrink(),
      AsyncStatus.busy => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(busyLabel),
          ],
        ),
      AsyncStatus.success => successLabel == null
          ? const SizedBox.shrink()
          : Text(successLabel!, style: const TextStyle(color: Colors.green)),
      AsyncStatus.failure => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                failureMessage ?? '오류가 발생했습니다.',
                style: const TextStyle(color: Colors.red),
              ),
            ),
            if (onRetry != null)
              TextButton(
                key: ValueKey('$statusId.retry.button'),
                onPressed: onRetry,
                child: const Text('재시도'),
              ),
          ],
        ),
    };

    return Semantics(
      identifier: statusId,
      value: status.name,
      liveRegion: status == AsyncStatus.failure,
      child: KeyedSubtree(key: ValueKey(statusId), child: content),
    );
  }
}
