# 남은 구현 계획

완료된 기능은 이 문서에 기록하지 않는다. 항목을 완료하면 관련 테스트와 함께
목록에서 제거한다.

## 배포 준비

- 소유자 계정의 Android release signing과 iOS Team·배포 signing을 구성한다.
  설정된 `com.bodymark.bodymark` 식별자의 스토어 등록 가능 여부도 배포 계정에서 확인한다.
- 출시용 브랜드 원본 자산과 시작 화면을 최종 확정한다. 현재 앱 아이콘은 기존
  벡터 심벌을 BodyMark 색상으로 렌더링한 개발용 자산이다.
- 출시 버전·빌드 번호를 확정하고 서명된 Android App Bundle과 iOS Archive/TestFlight
  후보를 생성해 `docs/device-smoke-checklist.md`를 완료한다.
- 스토어 설명·스크린샷·지원 및 개인정보처리방침 URL을 준비하고, Play Data Safety와
  App Store App Privacy 응답을 실제 데이터 처리와 일치시킨다. 앱은 네트워크로
  데이터를 전송하지 않으며 암호화 기능도 사용하지 않는다.

## 실기기 사용성 검증

- 강사와 함께 OT 및 장기 추적 촬영에서 거리·높이·투명도와 전신 표시를 확인한다.
- Android/iOS 실기기에서 카메라·사진 선택·저장·공유·권한 거부/재허용을 검증한다.
  시뮬레이터 실행·빌드 성공은 실제 카메라 및 기기 사진 보관함 검증을 대신하지 않는다.
- 작은 화면·큰 글자·스크린리더에서 입력, 촬영 셔터, 비교·공유를 검증한다.

## 기기 이전 검증

- 실기기에서 Android 기기 간 전송(D2D)으로 DB와 사진이 함께 옮겨지는지 확인하고,
  클라우드 자동 백업에는 앱 데이터가 포함되지 않는지 확인한다.
- 실기기에서 iOS Quick Start 전송과 iCloud 백업 복원으로 기록이 유지되는지
  확인한다.

## 추후 개선

- Flutter SDK를 올리기 전에 `camera_android_camerax`·`share_plus`의 Built-in
  Kotlin 지원 여부를 확인하고, 빌드 경고가 사라지는 호환 버전으로 갱신한다.
