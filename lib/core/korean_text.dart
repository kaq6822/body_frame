/// 낱자 사이 줄바꿈을 막는 보이지 않는 문자(WORD JOINER, U+2060).
///
/// 보이지 않는 문자라 소스에 그대로 넣으면 나중에 눈으로 찾을 수 없다.
/// 이스케이프로만 적는다.
const String _wordJoiner = '\u2060';

/// 줄바꿈 없는 공백(NO-BREAK SPACE, U+00A0).
const String _noBreakSpace = '\u00a0';

/// 한글 음절과 자모 범위.
///
/// 줄바꿈이 낱자 단위로 일어나는 것은 이 범위의 글자들이다. 영문과 숫자는 이미
/// 단어 단위로 끊기므로 손대지 않는다. 불필요하게 보조 문자를 끼우면 문자열이
/// 부풀고, 복사한 텍스트나 `Body Frame` 같은 고유명사 검색이 어긋난다.
bool _breaksBetweenLetters(int rune) =>
    (rune >= 0xac00 && rune <= 0xd7a3) || // 가–힣
    (rune >= 0x1100 && rune <= 0x11ff) || // 초성·중성·종성
    (rune >= 0x3130 && rune <= 0x318f); // 호환 자모

/// 어절 안쪽에서 줄이 끊기지 않게 한글 낱자 사이를 붙인다.
///
/// 한국어는 단어 경계가 공백으로만 드러나는데, 줄바꿈 규칙은 한글을 CJK로 보아
/// **아무 낱자 사이에서나** 줄을 넘긴다. 그래서 안내 문구가 "카메라 접근을 허용 /
/// 해주세요."처럼 어절 중간에서 끊기고, 읽는 사람이 끊긴 조각을 이어 붙여야 한다.
///
/// 한글끼리 맞닿은 자리에 [_wordJoiner]를 넣어 그 자리의 줄바꿈만 막는다. 공백은
/// 그대로 남으므로 **어절 경계에서만** 줄이 넘어간다. 스크린리더는 이 문자를
/// 무시하지만, 원문이 필요한 곳(`semanticsLabel`, 텍스트 비교)에는 변환하지 않은
/// 문자열을 함께 넘겨야 한다.
///
/// 어절 하나가 주어진 폭보다 길면 줄바꿈할 자리가 없어 그 어절은 여전히 끊긴다.
/// 폭을 넘겨 잘리는 것보다는 나으므로 그대로 둔다.
String keepPhrasesWhole(String text) {
  if (text.isEmpty) return text;
  final buffer = StringBuffer();
  int? previous;
  for (final rune in text.runes) {
    if (previous != null &&
        _breaksBetweenLetters(previous) &&
        _breaksBetweenLetters(rune)) {
      buffer.write(_wordJoiner);
    }
    buffer.writeCharCode(rune);
    previous = rune;
  }
  return buffer.toString();
}

/// 설정 경로 같은 단계 목록을 한 줄 문자열로 잇는다.
///
/// 단계 하나는 통째로 남아야 한다. 한글은 [keepPhrasesWhole]로 묶고, `Body Frame`
/// 처럼 단계 이름 안에 든 공백은 줄바꿈 없는 공백으로 바꿔 단계가 두 줄로 갈라지지
/// 않게 한다.
///
/// 단계와 뒤따르는 구분자도 줄바꿈 없는 공백으로 붙인다. 그래서 줄은 구분자
/// **다음**의 보통 공백에서만 넘어가고, 다음 줄이 구분자로 시작하는 일이 없다.
/// 화면 폭이 어떻든 "…권한 ›" 다음 줄에 "카메라"가 오는 모양으로 끊긴다.
String joinBreadcrumb(List<String> steps) => steps
    .map((step) => keepPhrasesWhole(step).replaceAll(' ', _noBreakSpace))
    .join('$_noBreakSpace› ');
