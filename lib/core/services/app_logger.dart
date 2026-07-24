import 'dart:convert';
import 'dart:developer' as developer;

/// 로그 수준.
enum LogLevel { debug, info, warn, error }

/// 기능 진행 단계. 시작/진행/성공/실패를 구조화 로그로 남긴다.
enum LogPhase { start, progress, success, failure }

/// 구조화 로거.
///
/// 기능 단계와 주요 렌더링 결과를 구조화해서 남기되 개인정보(회원
/// 이름/연락처/메모)와 인증 정보는 포함하지 않는다.
///
/// 로그는 `event`(안정적 키)와 선택적 `context`(민감정보 제외 메타데이터)로
/// 구성한다. 파일 경로/회원 이름 등 식별 가능한 값 대신 id나 카운트를 남긴다.
class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  /// 테스트에서 로그를 가로채기 위한 싱크. null이면 developer.log 사용.
  void Function(Map<String, dynamic> entry)? sink;

  void debug(String event, {Map<String, dynamic>? context}) =>
      _log(LogLevel.debug, event, context: context);

  void info(String event, {Map<String, dynamic>? context}) =>
      _log(LogLevel.info, event, context: context);

  void warn(String event, {Map<String, dynamic>? context}) =>
      _log(LogLevel.warn, event, context: context);

  void error(String event,
          {Map<String, dynamic>? context, Object? err, StackTrace? stack}) =>
      _log(LogLevel.error, event, context: context, err: err, stack: stack);

  /// 기능 단계 로그. 예: `phase('member.delete', LogPhase.success, {'count': 3})`.
  void phase(String feature, LogPhase phase, {Map<String, dynamic>? context}) {
    final level =
        phase == LogPhase.failure ? LogLevel.error : LogLevel.info;
    _log(level, '$feature.${phase.name}', context: context);
  }

  void _log(
    LogLevel level,
    String event, {
    Map<String, dynamic>? context,
    Object? err,
    StackTrace? stack,
  }) {
    final entry = <String, dynamic>{
      'ts': DateTime.now().toIso8601String(),
      'level': level.name,
      'event': event,
      if (context != null && context.isNotEmpty) 'context': context,
      if (err != null) 'error': err.toString(),
    };

    final localSink = sink;
    if (localSink != null) {
      localSink(entry);
      return;
    }

    developer.log(
      jsonEncode(entry),
      name: 'body_frame',
      level: _levelValue(level),
      error: err,
      stackTrace: stack,
    );
  }

  int _levelValue(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 500;
      case LogLevel.info:
        return 800;
      case LogLevel.warn:
        return 900;
      case LogLevel.error:
        return 1000;
    }
  }
}
