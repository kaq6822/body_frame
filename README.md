# Body Frame

회원의 체형 사진을 기기 안에 기록하고 날짜별로 비교하는 Android/iOS Flutter
앱입니다. 로그인이나 서버 없이 동작하며, 촬영·갤러리 등록, 기록 관리, 비교 이미지
생성, 앱 잠금, 백업·복원을 제공합니다.

## 실행

```sh
flutter pub get
flutter run
```

## 검증

```sh
flutter analyze
flutter test
```

스토어 제출 후보 빌드는 [실기기 스모크 테스트](docs/device-smoke-checklist.md)도
확인합니다.

개발 제약은 [AGENTS.md](AGENTS.md), 아직 남은 구현 범위는
[ROADMAP.md](ROADMAP.md)를 참고합니다.
