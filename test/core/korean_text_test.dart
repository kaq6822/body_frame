import 'package:body_frame/core/korean_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 한국어 줄바꿈 보정 검증.
///
/// 실기기 안내 문구가 "카메라 접근을 허용 / 해주세요."처럼 어절 중간에서 끊겨
/// 읽기 어려웠다. 문자열 변환만 보는 게 아니라 실제 텍스트 레이아웃으로 **줄이
/// 어디서 끊기는지**를 확인한다.
/// 어절 안쪽을 붙이는 WORD JOINER.
const wordJoiner = '\u2060';

/// 단계 안쪽을 붙이는 NO-BREAK SPACE.
const noBreakSpace = '\u00a0';

void main() {
  /// [text]를 [maxWidth]로 배치했을 때 각 줄의 문자열.
  List<String> layoutLines(String text, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontSize: 14, height: 1.4),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    final lines = <String>[];
    var start = 0;
    for (final metrics in painter.computeLineMetrics()) {
      // 줄 끝 지점을 오른쪽 끝 살짝 안쪽 좌표로 되짚어 경계를 찾는다.
      final end = painter
          .getPositionForOffset(
            Offset(metrics.width, metrics.baseline),
          )
          .offset;
      if (end <= start) continue;
      lines.add(text.substring(start, end));
      start = end;
    }
    if (start < text.length) lines.add(text.substring(start));
    return lines;
  }

  /// 보이지 않는 보조 문자를 걷어낸 사람이 읽는 형태.
  String visible(String text) =>
      text.replaceAll(wordJoiner, '').replaceAll(noBreakSpace, ' ').trim();

  group('keepPhrasesWhole', () {
    test('어절 사이 공백은 그대로 두고 낱자 사이만 붙인다', () {
      final joined = keepPhrasesWhole('카메라 접근');

      // 공백 개수가 유지되어야 어절 경계에서 줄이 넘어갈 수 있다.
      expect(joined.split(' ').length, 2);
      expect(visible(joined), '카메라 접근');
      expect(joined.contains(wordJoiner), isTrue);
    });

    test('빈 문자열은 그대로 돌려준다', () {
      expect(keepPhrasesWhole(''), '');
    });

    test('영문과 숫자에는 보조 문자를 넣지 않는다', () {
      // 영문은 이미 단어 단위로 끊긴다. 끼워 넣으면 문자열이 부풀고 'Body Frame'
      // 같은 고유명사 검색과 복사가 어긋난다.
      expect(keepPhrasesWhole('Body Frame'), 'Body Frame');
      expect(keepPhrasesWhole('iOS 18'), 'iOS 18');
    });

    test('한글과 영문이 섞인 어절은 한글 쪽만 묶는다', () {
      final joined = keepPhrasesWhole('카메라Body');

      // 한글끼리 맞닿은 자리에만 들어가므로 한글 3글자 사이 2곳.
      expect(joined.split(wordJoiner).length - 1, 2);
      expect(visible(joined), '카메라Body');
    });

    test('보정하지 않으면 어절 중간에서 끊기고, 보정하면 어절 경계에서만 끊긴다', () {
      const sentence = '촬영을 시작하려면 기기 설정에서 카메라 접근을 허용해주세요.';
      const width = 150.0;

      final rawLines = layoutLines(sentence, width);
      final fixedLines = layoutLines(keepPhrasesWhole(sentence), width);

      // 두 경우 모두 여러 줄이어야 비교가 의미 있다.
      expect(rawLines.length, greaterThan(1));
      expect(fixedLines.length, greaterThan(1));

      // 보정 전에는 어절 중간에서 끊긴 줄이 있다.
      expect(
        rawLines.any((line) => !_endsAtPhraseBoundary(visible(line), sentence)),
        isTrue,
        reason: '보정 전에는 낱자 사이가 끊겨야 이 테스트가 의미를 가진다',
      );

      // 보정 후에는 마지막 줄을 뺀 모든 줄이 어절 경계에서 끝난다.
      for (final line in fixedLines.take(fixedLines.length - 1)) {
        expect(
          _endsAtPhraseBoundary(visible(line), sentence),
          isTrue,
          reason: '"${visible(line)}"은 어절 경계에서 끝나야 한다',
        );
      }
    });
  });

  group('joinBreadcrumb', () {
    test('단계 사이를 구분자로 잇고 읽을 때는 원문이 남는다', () {
      final joined = joinBreadcrumb(['설정', '권한', '카메라']);

      expect(visible(joined), '설정 › 권한 › 카메라');
    });

    test('단계 이름 안의 공백은 줄바꿈되지 않아 단계가 쪼개지지 않는다', () {
      final joined = joinBreadcrumb(['설정', 'Body Frame']);

      // 'Body Frame'이 두 줄로 갈라지면 경로의 한 단계가 쪼개진 것이다.
      expect(joined.contains('Body\u00a0Frame'), isTrue);
      expect(joined.contains('Body Frame'), isFalse);
      expect(visible(joined), '설정 › Body Frame');
    });

    test('줄이 넘어갈 때 다음 줄이 구분자로 시작하지 않는다', () {
      final path = joinBreadcrumb([
        '설정',
        '애플리케이션',
        'Body Frame',
        '권한',
        '카메라',
      ]);

      final lines = layoutLines(path, 180);
      expect(lines.length, greaterThan(1), reason: '여러 줄이어야 비교가 의미 있다');

      for (final line in lines.skip(1)) {
        expect(
          visible(line).startsWith('›'),
          isFalse,
          reason: '"${visible(line)}"이 구분자로 시작하면 경로를 따라가기 어렵다',
        );
      }
    });
  });
}

/// [line]이 [sentence]의 어절 경계에서 끝나는지.
bool _endsAtPhraseBoundary(String line, String sentence) {
  final trimmed = line.trimRight();
  if (trimmed.isEmpty) return true;
  final next = sentence.indexOf(trimmed) + trimmed.length;
  // 문장 끝이거나, 다음 글자가 공백이면 어절이 온전히 끝난 것이다.
  return next >= sentence.length || sentence[next] == ' ';
}
