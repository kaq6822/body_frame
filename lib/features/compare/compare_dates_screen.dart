import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models/models.dart';
import '../../core/router/app_routes.dart';
import 'compare_providers.dart';

/// compareDates -> compareDirection 쿼리 파라미터 키.
/// [AppParams]에는 촬영 기록 id 쌍이 정의되어 있지 않아 이 feature 안에서만
/// 쓰는 이름을 별도로 둔다(경로 문자열 자체는 여전히 goNamed로만 다룬다).
class CompareQueryKeys {
  CompareQueryKeys._();
  static const beforeRecordId = 'beforeRecordId';
  static const afterRecordId = 'afterRecordId';
}

final _dateFormat = DateFormat('yyyy.MM.dd');

/// 비교 날짜 선택 화면.
///
/// 이전/이후 촬영일(=촬영 기록)을 고르고 위치를 교환할 수 있다.
class CompareDatesScreen extends ConsumerStatefulWidget {
  static const screenId = 'screen.compare.dates';

  const CompareDatesScreen({super.key});

  @override
  ConsumerState<CompareDatesScreen> createState() => _CompareDatesScreenState();
}

class _CompareDatesScreenState extends ConsumerState<CompareDatesScreen> {
  String? _beforeRecordId;
  String? _afterRecordId;
  bool _defaultsApplied = false;

  void _applyDefaults(List<PhotoRecord> records) {
    if (_defaultsApplied || records.length < 2) return;
    // listAll은 최신 촬영일이 먼저 온다.
    // 이후=가장 최근, 이전=그다음으로 최근인 기록을 기본값으로 제안한다.
    _afterRecordId = records.first.id;
    _beforeRecordId = records[1].id;
    _defaultsApplied = true;
  }

  Future<void> _pickRecord({
    required bool isBefore,
    required List<PhotoRecord> records,
  }) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        final unavailableRecordId = isBefore ? _afterRecordId : _beforeRecordId;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: records.map((record) {
              final isUnavailable = record.id == unavailableRecordId;
              return ListTile(
                key: ValueKey(
                  'compare.${isBefore ? 'before' : 'after'}.date.option.${record.id}',
                ),
                title: Text(_dateFormat.format(record.shotAt)),
                subtitle: record.memo == null ? null : Text(record.memo!),
                enabled: !isUnavailable,
                onTap: isUnavailable
                    ? null
                    : () => Navigator.of(context).pop(record.id),
              );
            }).toList(),
          ),
        );
      },
    );
    if (selected == null) return;
    setState(() {
      if (isBefore) {
        _beforeRecordId = selected;
      } else {
        _afterRecordId = selected;
      }
    });
  }

  void _swap() {
    setState(() {
      final tmp = _beforeRecordId;
      _beforeRecordId = _afterRecordId;
      _afterRecordId = tmp;
    });
  }

  void _goNext() {
    final beforeId = _beforeRecordId;
    final afterId = _afterRecordId;
    if (beforeId == null || afterId == null || beforeId == afterId) return;
    context.pushNamed(
      AppRoutes.compareDirection,
      queryParameters: {
        CompareQueryKeys.beforeRecordId: beforeId,
        CompareQueryKeys.afterRecordId: afterId,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final recordsAsync = ref.watch(allRecordsProvider);

    return Semantics(
      identifier: CompareDatesScreen.screenId,
      container: true,
      label: '비교 날짜 선택',
      child: Scaffold(
        key: const ValueKey(CompareDatesScreen.screenId),
        appBar: AppBar(title: const Text('비교 날짜 선택')),
        body: recordsAsync.when(
          loading: () => const _StatusBody(
            key: ValueKey('screen.compare.dates.status'),
            state: _AsyncState.loading,
            message: '촬영 기록을 불러오는 중입니다.',
          ),
          error: (error, stack) => _StatusBody(
            key: const ValueKey('screen.compare.dates.status'),
            state: _AsyncState.error,
            message: '촬영 기록을 불러오지 못했습니다.',
            onRetry: () => ref.invalidate(allRecordsProvider),
          ),
          data: (records) {
            if (records.length < 2) {
              return const _StatusBody(
                key: ValueKey('screen.compare.dates.status'),
                state: _AsyncState.empty,
                message: '비교하려면 촬영 기록이 2개 이상 필요합니다.',
              );
            }
            _applyDefaults(records);
            final beforeRecord = records
                .where((r) => r.id == _beforeRecordId)
                .firstOrNull;
            final afterRecord = records
                .where((r) => r.id == _afterRecordId)
                .firstOrNull;
            final canProceed =
                beforeRecord != null &&
                afterRecord != null &&
                beforeRecord.id != afterRecord.id;

            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '비교할 이전/이후 촬영일을 선택하세요.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    identifier: 'compare.before.date.button',
                    label: '이전 촬영일 선택',
                    value: beforeRecord == null
                        ? '선택 안 됨'
                        : _dateFormat.format(beforeRecord.shotAt),
                    child: OutlinedButton(
                      key: const ValueKey('compare.before.date.button'),
                      onPressed: () =>
                          _pickRecord(isBefore: true, records: records),
                      child: Text(
                        beforeRecord == null
                            ? '이전 촬영일 선택'
                            : '이전: ${_dateFormat.format(beforeRecord.shotAt)}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Semantics(
                      identifier: 'compare.swap.button',
                      label: '이전/이후 위치 교환',
                      child: IconButton(
                        key: const ValueKey('compare.swap.button'),
                        icon: const Icon(Icons.swap_vert),
                        onPressed: _swap,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    identifier: 'compare.after.date.button',
                    label: '이후 촬영일 선택',
                    value: afterRecord == null
                        ? '선택 안 됨'
                        : _dateFormat.format(afterRecord.shotAt),
                    child: OutlinedButton(
                      key: const ValueKey('compare.after.date.button'),
                      onPressed: () =>
                          _pickRecord(isBefore: false, records: records),
                      child: Text(
                        afterRecord == null
                            ? '이후 촬영일 선택'
                            : '이후: ${_dateFormat.format(afterRecord.shotAt)}',
                      ),
                    ),
                  ),
                  const Spacer(),
                  Semantics(
                    identifier: 'compare.dates.next.button',
                    label: '다음: 촬영 방향 선택',
                    child: ElevatedButton(
                      key: const ValueKey('compare.dates.next.button'),
                      onPressed: canProceed ? _goNext : null,
                      child: const Text('다음'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

enum _AsyncState { loading, error, empty }

class _StatusBody extends StatelessWidget {
  final _AsyncState state;
  final String message;
  final VoidCallback? onRetry;

  const _StatusBody({
    super.key,
    required this.state,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state == _AsyncState.loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: CircularProgressIndicator(),
              ),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextButton(
                  onPressed: onRetry,
                  child: const Text('다시 시도'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
