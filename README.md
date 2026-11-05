# BodyMark · 바디마크

필라테스·요가·피트니스 강사가 휴대폰에서 회원의 레슨과 체형 변화를 기록하는
Android와 iOS(15 이상)를 지원하는 오프라인 Flutter 앱입니다. 로그인·서버·자체 클라우드 동기화가 없습니다.

- 회원별 운동 배경·목표·통증/주의사항·전달 내용·강사 관찰·메모
- 실제 레슨 날짜·시각을 지정한 일지: 일지만, 사진만, 일지와 사진 모두 저장
- 수업 전·후·정기 사진, 정면 → 좌측면 → 우측면 → 후면 순서의 촬영·재촬영·건너뛰기
- 같은 회원·같은 방향의 이전 사진 가이드, 저장 전 레슨 사진도 기준으로 사용
- 회원별 나란히·겹쳐 비교, 원본 비율을 유지하는 이미지 생성·저장·공유
- 회원 이름과 메모는 공유 이미지에 기본 비포함

Dart 프로젝트/패키지명은 `bodymark`, 앱 표시 이름은 `BodyMark`, Android application ID와
iOS bundle ID는 `com.bodymark.bodymark`입니다. 작업 폴더 이름은 기존 워크스페이스 경로를 유지합니다.
기존 `com.bodyframe.*` 설치본과는 별도 앱으로 설치되므로 OS가 이전 앱의 샌드박스를 자동으로
새 식별자에 넘겨주지 않습니다. 동일 앱 컨테이너에 있는 v1 DB는 v2로 이전하며 사진·일지를
보존합니다. DB 파일명 `body_frame.db`는 이 이전을 위해 유지합니다. 기존 기록은 회원 미연결로
남기고 사용자가 회원과 실제 레슨 일시를 확인해 연결합니다.

데이터 이전은 OS의 기기 간 전송 정책에 따릅니다. 앱 내 백업/복원 기능은 없습니다.

## 실행과 검증

```sh
flutter pub get
flutter run
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --simulator --no-codesign
```

[디자인 검수본](docs/design/bodymark-design-review.md), [개발 지침](AGENTS.md),
[남은 구현·배포 준비](ROADMAP.md), [실기기 체크리스트](docs/device-smoke-checklist.md)를 참고합니다.
