import 'package:flutter/material.dart';
import '../members/ui.dart';

class CaptureGuideScreen extends StatelessWidget {
  const CaptureGuideScreen({super.key});
  @override
  Widget build(BuildContext context) => mark(
    'screen.capture.guide',
    Scaffold(
      appBar: AppBar(title: const Text('촬영 가이드')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          section(
            '촬영 전에',
            const Text(
              '머리부터 발끝까지 프레임에 들어오도록 거리를 확보해주세요. 같은 장소·조명·높이를 유지하면 이전 기록과 비교하기 좋아요.',
            ),
          ),
          section(
            '같은 방향의 이전 사진',
            const Text(
              '선택한 회원의 같은 방향 사진만 반투명하게 표시해요. 발 위치와 머리 높이를 참고하며 휴대폰의 거리와 높이를 조절해주세요. 자동으로 몸을 정렬하거나 보정하지는 않아요.',
            ),
          ),
          section(
            '네 방향을 순서대로',
            const Text(
              '정면 → 좌측면 → 우측면 → 후면 순서예요. 모든 방향이 필수는 아니에요. 촬영 확인에서 각 방향을 다시 찍거나 일부 사진만 일지에 연결할 수 있어요.',
            ),
          ),
          section(
            '촬영하지 못한 날에도',
            const Text('사진 없이 수업 일지만 저장할 수 있어요. 실제 레슨 일시와 사진 촬영 시각은 각각 기록돼요.'),
          ),
        ],
      ),
    ),
  );
}
