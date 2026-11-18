import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/korean_text.dart';
import '../../core/theme/app_tokens.dart';
import '../members/ui.dart';

/// 데이터 보관 안내(45)와 개인정보 안내(46). 두 화면은 서로 이동할 수 있다.
class InformationScreen extends StatelessWidget {
  final bool privacy;
  const InformationScreen({super.key, this.privacy = false});

  @override
  Widget build(BuildContext context) {
    final cards = privacy ? _privacyCards : _dataCards;
    final prefix = privacy ? 'settings.privacy' : 'settings.data';
    return mark(
      privacy ? 'screen.settings.privacy' : 'screen.settings.data',
      Scaffold(
        appBar: AppBar(title: Text(privacy ? '개인정보 안내' : '데이터 보관 안내')),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.sp4),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sp4),
              child: Text(
                keepPhrasesWhole(
                  privacy
                      ? '외부 계정이나 서버 전송 없이, 이 기기 안에서 회원 정보와 사진을 다뤄요.'
                      : '로그인이나 서버 없이, 이 기기에 직접 기록하는 오프라인 앱이에요.',
                ),
                key: ValueKey('$prefix.intro'),
                style: context.texts.bodyLarge?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
            for (final card in cards) _InfoCard(card),
            if (!privacy) const _BackupNote(),
            const SizedBox(height: AppSpacing.sp2),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: ValueKey('$prefix.link'),
                onPressed: () => context.pushReplacement(
                  privacy ? '/settings/data' : '/settings/privacy',
                ),
                icon: Icon(
                  privacy
                      ? Icons.phone_android_outlined
                      : Icons.privacy_tip_outlined,
                ),
                label: Text(privacy ? '데이터 보관 안내 보기' : '개인정보 안내 보기'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _dataCards = [
    _CardData(
      Icons.phone_android_outlined,
      '이 기기의 앱 저장소에 보관해요',
      '회원 정보·일지·사진은 앱 저장소에 보관돼요. 앱 자체 클라우드 동기화나 앱 안의 백업·복원 기능은 없어요. 앱을 삭제하면 기록도 사라질 수 있어요.',
    ),
    _CardData(
      Icons.swap_horiz,
      '기기를 바꿀 때',
      '앱 안에서 옮기는 기능은 없어요. 새 기기로 옮길 때는 Android의 기기 간 전송이나 iOS의 Quick Start 같은 시스템 전송을 이용해요. 전송 결과는 기기와 시스템 설정에 따라 달라질 수 있으니, 옮긴 뒤 기록이 모두 있는지 확인해주세요.',
    ),
    _CardData(
      Icons.photo_outlined,
      '사진 원본 유지',
      '원본을 자동으로 자르거나 몸의 모양을 보정하지 않아요. 격자와 이전 사진은 촬영·표시 보조 수단이에요. 공유 이미지는 원본과 별도로 생성해요.',
    ),
  ];

  static const _privacyCards = [
    _CardData(
      Icons.person_outline,
      '회원 정보와 사진',
      '이름, 운동 목표, 통증·주의사항, 레슨 일지와 체형 사진은 이 앱의 기기 저장소에 보관돼요. 회원에게 기록 목적을 설명하고 필요한 정보만 입력해주세요.',
    ),
    _CardData(
      Icons.cloud_off_outlined,
      '앱 자체 전송 없음',
      'BodyMark는 로그인·자체 서버·클라우드 동기화를 사용하지 않아요. 사진을 공유하면 선택한 앱으로 이미지가 전달돼요.',
    ),
    _CardData(
      Icons.camera_alt_outlined,
      '접근 권한',
      '카메라와 사진은 촬영하거나 가져올 때 필요한 권한만 요청해요.',
    ),
    _CardData(
      Icons.ios_share,
      '공유 전 확인',
      '회원 이름과 일지 메모는 기본으로 포함하지 않아요. 내보내기 미리보기에서 포함 내용을 확인하고, 회원의 사진을 다른 사람에게 전달하기 전에 공유 동의를 확인해주세요.',
    ),
    _CardData(
      Icons.delete_outline,
      '삭제',
      '사진 한 장, 레슨 전체, 회원 전체를 구분해 삭제할 수 있어요. 삭제 전 확인창에서 범위를 알려드려요. 다른 앱에 이미 공유한 사본은 이 앱에서 지울 수 없어요.',
    ),
  ];
}

class _CardData {
  final IconData icon;
  final String title;
  final String body;
  const _CardData(this.icon, this.title, this.body);
}

class _InfoCard extends StatelessWidget {
  final _CardData data;
  const _InfoCard(this.data);

  @override
  Widget build(BuildContext context) {
    return panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(data.icon, color: context.colors.primary),
          const SizedBox(width: AppSpacing.sp3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data.title, style: context.texts.titleMedium),
                const SizedBox(height: AppSpacing.sp2),
                Text(
                  keepPhrasesWhole(data.body),
                  style: context.texts.bodyMedium?.copyWith(
                    height: 1.6,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 공유 이미지 저장을 전체 백업으로 오해하지 않게 알린다.
class _BackupNote extends StatelessWidget {
  const _BackupNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('settings.data.backupNote'),
      padding: const EdgeInsets.all(AppSpacing.sp4),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: context.colors.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sp3),
          Expanded(
            child: Text(
              keepPhrasesWhole('공유 이미지 저장은 선택한 이미지만 내보내요. 전체 기록의 백업과는 달라요.'),
              style: context.texts.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
