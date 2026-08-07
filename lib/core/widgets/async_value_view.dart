import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 비동기 상태를 진행/성공/실패로 구분해 표시하는 공용 위젯.
///
/// 상태 표시 위젯에 `screen.<x>.status` 식별자를 부여하고 실패 시 재시도
/// 액션과 재시도 가능한 일반 오류 문구를 노출한다. 예외 원문에는 로컬
/// 경로나 데이터베이스 값이 포함될 수 있으므로 화면에 직접 표시하지 않는다.
/// 대기(idle) 상태는 호출부가 [AsyncValue]를 만들기 전(예: 액션 실행 전)에
/// 해당하므로 이 위젯 바깥에서 표현한다.
class AsyncValueView<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final String statusId;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  const AsyncValueView({
    super.key,
    required this.value,
    required this.statusId,
    required this.builder,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: (data) => Semantics(
        identifier: statusId,
        liveRegion: true,
        label: '표시 완료',
        child: KeyedSubtree(key: ValueKey(statusId), child: builder(data)),
      ),
      loading: () => Semantics(
        identifier: statusId,
        liveRegion: true,
        label: '불러오는 중',
        child: KeyedSubtree(
          key: ValueKey(statusId),
          child: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
        ),
      ),
      error: (error, _) => Semantics(
        identifier: statusId,
        liveRegion: true,
        label: '불러오지 못했습니다',
        child: KeyedSubtree(
          key: ValueKey(statusId),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 40),
                  const SizedBox(height: 8),
                  const Text('불러오지 못했습니다', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  if (onRetry != null)
                    FilledButton(
                      key: ValueKey('$statusId.retry.button'),
                      onPressed: onRetry,
                      child: const Text('다시 시도'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
