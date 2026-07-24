import 'package:flutter/material.dart';

/// 개인정보 및 이용 안내 화면.
///
/// 로그인/서버 없이 기기 내부에만 데이터가 저장된다는 점, 앱 삭제 시 데이터가
/// 함께 삭제될 수 있다는 점, 백업 권장 사항을 안내하는 정적 화면.
class PrivacyInfoScreen extends StatelessWidget {
  static const screenId = 'screen.settings.privacy';

  const PrivacyInfoScreen({super.key});

  static const _items = [
    (
      icon: Icons.smartphone,
      title: '기기 내부 저장',
      body: '회원 정보와 체형 사진은 서버나 클라우드가 아닌 이 기기 내부에만 저장됩니다. '
          '인터넷 연결이 없어도 주요 기능을 사용할 수 있습니다.',
    ),
    (
      icon: Icons.warning_amber_outlined,
      title: '앱 삭제 시 데이터 소실',
      body: '앱을 삭제하면 기기에 저장된 회원 정보와 사진이 함께 삭제될 수 있습니다. '
          '기기 변경이나 재설치 전에는 반드시 백업 및 복원 기능으로 데이터를 미리 내보내 주세요.',
    ),
    (
      icon: Icons.folder_special_outlined,
      title: '앱 전용 저장소',
      body: '촬영한 사진은 앱 전용 저장소에 보관되어 일반 사진 갤러리에 자동으로 노출되지 않습니다. '
          '사용자가 명시적으로 내보내기나 공유를 선택한 경우에만 외부로 전달됩니다.',
    ),
    (
      icon: Icons.lock_outline,
      title: '앱 잠금',
      body: '설정에서 PIN, 비밀번호 또는 생체 인증으로 앱 잠금을 사용할 수 있습니다. '
          '잠금을 사용 중이면 앱이 백그라운드로 이동할 때 화면이 가려집니다.',
    ),
    (
      icon: Icons.no_accounts_outlined,
      title: '로그인 없음',
      body: '이 앱은 회원가입이나 로그인을 사용하지 않는 독립 실행형 애플리케이션입니다.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: screenId,
      container: true,
      label: '개인정보 및 이용 안내',
      child: Scaffold(
        key: const ValueKey(screenId),
        appBar: AppBar(title: const Text('개인정보 및 이용 안내')),
        body: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _items.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            final item = _items[index];
            return ListTile(
              key: ValueKey('privacy.item.$index'),
              leading: Icon(item.icon),
              title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(item.body),
              ),
              isThreeLine: true,
            );
          },
        ),
      ),
    );
  }
}
