# 남은 구현 계획

완료된 기능은 이 문서에 기록하지 않는다. 항목을 완료하면 관련 테스트와 함께
목록에서 제거한다.

## 배포 준비

- 소유자 계정과 식별자를 확정한 뒤 Android application ID·release signing,
  iOS bundle ID·Team·배포 signing을 구성한다.
- 브랜드 원본 자산을 확정한 뒤 Android/iOS 앱 아이콘과 시작 화면을 교체한다.
- 출시 버전·빌드 번호를 확정하고 서명된 Android App Bundle과 iOS Archive/TestFlight
  후보를 생성해 `docs/device-smoke-checklist.md`를 완료한다.
- 스토어 설명·스크린샷·지원 및 개인정보처리방침 URL을 준비하고, Play Data Safety,
  App Store App Privacy와 암호화 수출 규정 응답을 실제 데이터 처리와 일치시킨다.

## 추후 개선

- 대용량 백업에서 파일 전체를 메모리에 올리지 않도록 ZIP 생성·검증과 암호화·복호화를
  스트리밍 방식으로 바꾸고, 저사양 실기기의 메모리 사용량을 회귀 테스트한다.
- Flutter SDK를 올리기 전에 `camera_android_camerax`·`share_plus`의 Built-in
  Kotlin 지원과 `flutter_secure_storage`의 iOS Swift Package Manager 지원 여부를
  확인하고, 빌드 경고가 사라지는 호환 버전으로 갱신한다.
