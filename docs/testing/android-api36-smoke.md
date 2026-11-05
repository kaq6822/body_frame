# Android API 36 에뮬레이터 검증

검증일: 2026-10-07. `cw_api36`, Android 16/API 36, arm64, 1080×2400,
420dpi. Body Frame 1.0.0+1 debug APK를 Flutter CLI로 빌드하고 ADB로 설치·조작했다.
실제 camera, image_picker, sqflite, shared_preferences, gal 플러그인을 사용했다.

## 확인 결과

| 항목 | 결과 및 증거 |
| --- | --- |
| Android 빌드·설치 | `flutter build apk --debug`, `adb install -r` 성공 |
| 앱 이름·권한 | Body Frame 카메라 권한 팝업 확인. 설치 권한에 CAMERA 존재, RECORD_AUDIO·READ_MEDIA_IMAGES·READ_EXTERNAL_STORAGE 없음 |
| 카메라 촬영 | 셔터로 정면 촬영 후 `2 / 4 · 좌측면`으로 자동 전환 |
| 촬영 리뷰 저장 | 저장 진행 상태와 재촬영·날짜·저장 비활성화 확인. 완료 후 카메라 복귀, 기록 1건 및 이전 사진 가이드 표시 |
| 시스템 갤러리 선택 | Android Photo Picker로 사진 선택. 추가 저장소 권한 팝업 없이 등록 목록으로 복귀 |
| 방향 필수 입력 | 미지정 시 저장 비활성화, 정면 지정 후 저장 가능 |
| 갤러리 저장 | 기록 2건·사진 2장. 같은 날 두 기록이 합쳐지지 않음 |
| 설정 저장 | 격자 색상 연속 변경 및 피드백 스위치 변경 후 성공 상태. shared_preferences에 마지막 색상 4294961979(cyan), countdownFeedback=false 저장 |
| 재실행 | force-stop/start 후 카메라와 기록 2건 재확인 |
| 저장 경로·원본 | DB의 사진 경로 모두 `photos/202610/...` 상대경로. 가져온 JPEG SHA-256이 입력과 동일 |
| 비교 | 본인 기록 두 건 자동 선택, 0일 간격, 공통 정면만 활성화. 비교·내보내기 화면 진입 |
| 이미지 생성·갤러리 저장 | 생성 성공, 사진 보관함 저장 완료 안내. MediaStore와 `Pictures/BodyFrame/compare_front_20261007_20261007.png` 확인 |
| 이미지 구성 | 결과 PNG를 열어 원본 비율·전체 세로 사진·여백 및 날짜·격자 확인 |
| 오류 로그 | 검증 구간 logcat에서 앱 FATAL EXCEPTION, Flutter 오류, RenderFlex overflow, 앱 ANR 패턴 발견되지 않음 |

입력 원본과 저장된 JPEG의 SHA-256:
`f6ebf03243922b430db57a6e3dcde6bf80e52ff19d52dd0f804341d16c06b0b5`.

생성 파일: [Android 비교 결과](android-api36-compare.png).
카메라 이미지는 에뮬레이터 합성 장면, 가져온 사진은 테스트용 기하 도형이다.

## 검증 한계

- 기존 스냅샷 부팅에서 ADB 입력 무응답이 발생해 스냅샷 없이 콜드 부팅했다.
  이후 Android System UI 응답 없음 팝업을 닫고 위 기능 검증을 진행했다.
- 카메라 권한 거부 직후 재요청과 에뮬레이터 응답 문제가 겹쳤다. 거부·재시도
  흐름은 통과로 처리하지 않았다.
- 갤러리 저장 직후 ADB 뒤로가기를 보냈지만 완료 시점과 겹쳤다. 저장 중 뒤로가기
  차단을 네이티브에서 검증했다고 간주하지 않는다.
- 비행기 모드 재실행 구간에서 시작 화면에 머무르고 접근성 트리 수집이 실패했다.
  비행기 모드는 검증 후 해제했다. 앱·디버그 런타임·에뮬레이터 원인은 확정하지 않았으며 오프라인 시나리오는
  통과로 처리하지 않았다.
- 저장 지연·실패·복구 결과 도착과 설정 저장 큐 중간 상태는 결정론적 회귀 테스트로
  검증했다. 이전 수정 검증은 `flutter analyze` 오류 없음, `flutter test` 302개 통과.
  이번 ADB 테스트가 실패 주입 테스트를 대체하지 않는다.
- API 29, 태블릿, 실제 Android/iOS, 외부 공유 완료, D2D 이전은 이번 범위에서
  확인하지 않았다. 남은 작업은 ROADMAP.md와 실기기 체크리스트를 따른다.

## 재현 명령

```sh
flutter emulators --launch cw_api36
flutter build apk --debug
ADB="$HOME/Library/Android/sdk/platform-tools/adb"
"$ADB" -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
"$ADB" -s emulator-5554 shell am start -n com.bodyframe.body_frame/.MainActivity
"$ADB" -s emulator-5554 shell uiautomator dump /sdcard/body-frame-ui.xml
"$ADB" -s emulator-5554 shell cat /sdcard/body-frame-ui.xml
"$ADB" -s emulator-5554 shell input tap X Y
"$ADB" -s emulator-5554 shell input keyevent KEYCODE_BACK
```

접근성 트리의 `resource-id`에 `Semantics.identifier`가 노출된다. 화면 전환 시
`null root node`가 발생하면 이전 XML을 재사용하지 말고 새 덤프 성공을 기다린다.
로컬 상세 증거는 `/tmp/body-frame-android-smoke/`, 빌드 로그는
`/tmp/body-frame-android-build.log`에 저장했다.
