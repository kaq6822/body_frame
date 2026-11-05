import 'package:flutter/material.dart';
import '../members/ui.dart';

class InformationScreen extends StatelessWidget {
  final bool privacy;
  const InformationScreen({super.key, this.privacy = false});
  @override
  Widget build(BuildContext context) => mark(
    privacy ? 'screen.settings.privacy' : 'screen.settings.data',
    Scaffold(
      appBar: AppBar(title: Text(privacy ? '개인정보 안내' : '데이터 보관 안내')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: privacy
            ? [
                section(
                  '회원 정보와 사진',
                  const Text(
                    '이름, 운동 목표, 통증·주의사항, 레슨 일지와 체형 사진은 이 앱의 기기 저장소에 보관돼요. 회원에게 기록 목적을 설명하고 필요한 정보만 입력해주세요.',
                  ),
                ),
                section(
                  '앱 자체 전송 없음',
                  const Text(
                    'BodyMark는 로그인·자체 서버·클라우드 동기화를 사용하지 않아요. 사진을 공유하면 사용자가 선택한 앱으로 이미지가 전달돼요.',
                  ),
                ),
                section(
                  '공유 전 확인',
                  const Text(
                    '회원 이름과 일지 메모는 기본으로 포함하지 않아요. 내보내기 미리보기에서 포함 내용을 확인하고, 회원의 사진을 다른 사람에게 전달하기 전에 공유 동의를 확인해주세요.',
                  ),
                ),
                section(
                  '삭제',
                  const Text(
                    '사진 한 장, 레슨 전체, 회원 전체를 구분해 삭제할 수 있어요. 삭제 전 확인창에서 범위를 알려드려요. 다른 앱에 이미 공유한 사본은 이 앱에서 지울 수 없어요.',
                  ),
                ),
              ]
            : [
                section(
                  '휴대폰의 앱 저장소에 보관',
                  const Text(
                    '회원 정보·일지·사진은 앱 저장소에 보관돼요. 앱 자체 클라우드 동기화나 앱 내 백업·복원 기능은 제공하지 않아요. 앱을 삭제하면 기록도 사라질 수 있어요.',
                  ),
                ),
                section(
                  '기기를 바꿀 때',
                  const Text(
                    'Android는 운영체제의 기기 간 전송을 이용해요. iOS는 Quick Start와 OS 백업·복원 정책을 따라요. OS의 전송·백업 여부와 성공 결과는 기기 및 시스템 설정에 따라 달라져요.',
                  ),
                ),
                section(
                  '사진 원본 유지',
                  const Text(
                    '원본을 자동으로 자르거나 몸의 모양을 보정하지 않아요. 격자와 이전 사진은 촬영·표시 보조 수단이에요. 공유 이미지는 원본과 별도로 생성해요.',
                  ),
                ),
              ],
      ),
    ),
  );
}
