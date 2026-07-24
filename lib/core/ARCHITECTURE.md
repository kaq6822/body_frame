# body_frame 공통 아키텍처 (워커 필독)

이 문서는 `lib/features/<영역>/` 하위에서 병렬 작업하는 워커(members / capture /
records / compare / settings)가 반드시 따라야 할 규칙과 공용 API를 정의한다.

## 0. 절대 원칙 (MVP.md 15·19장)

- 사진 파일은 DB에 넣지 않는다. `BodyPhoto.filePath`로 **경로만** 저장한다.
- 원본 이미지를 자동으로 크롭/변형/덮어쓰지 않는다. 표시는 항상 `BoxFit.contain`.
- 네트워크 코드 금지(로그인/서버/클라우드 없음).
- 모든 ID는 `uuid` 사용: `const Uuid().v4()`.
- 삭제/복원/전체 교체 등 데이터 손실 작업은 반드시 확인 다이얼로그 뒤에 실행.
- 개인정보(이름/연락처/메모)와 사진 경로는 로그에 남기지 않는다.

## 1. 폴더 규칙

- 워커는 **자기 feature 폴더만** 수정한다. `lib/core/**`, `pubspec.yaml`,
  `analysis_options.yaml`은 수정하지 않는다(변경 필요 시 team-lead에 요청).
- 공용 코드가 필요하면 core에 추가 요청. feature 간 직접 import 금지.

## 2. 모델 (`lib/core/models/`, 배럴: `models/models.dart`)

`import 'package:body_frame/core/models/models.dart';`

### Member
`id, name(필수), avatarPath?, gender(Gender), birth?, contact?, memo?, createdAt, updatedAt`
- `Gender { male, female, other, unspecified }` — `.label`(한국어), `.key`, `Gender.fromKey()`
- `copyWith({..., bool clearAvatar})`, `toMap()`/`Member.fromMap()`

### PhotoRecord (촬영 기록 = 특정 날짜의 사진 묶음)
`id, memberId, shotAt(촬영일), memo?, createdAt, updatedAt`

### BodyPhoto (개별 체형 사진)
`id, recordId, filePath, direction(BodyDirection), width, height, orientation(EXIF 1~8), gridSettings(GridSettings), memo?, createdAt`

### BodyDirection (enum)
`front, leftSide, rightSide, back, etc` — `.label`(정면/좌측면/우측면/후면/기타), `.key`, `BodyDirection.fromKey()`
좌·우 측면은 반드시 구분한다.

### GridSettings
`visible, opacity(0~1), lineWidth, spacing, colorValue(ARGB int)`
- `GridSettings.defaults`, `copyWith`, `toMap`/`fromMap`, `toJson`/`fromJson`

### AppSettings
`lockMode(LockMode), biometricEnabled, autoLockSeconds, defaultGrid(GridSettings), defaultExportOptions(ExportImageOptions), studioName?, studioLogoPath?, dataNoticeAcknowledged`
- `LockMode { none, password, pin, biometric }`
- `ExportImageOptions { includeMemberName(기본 false), includeShotDate, includeMemo, includeGrid, includeStudioName, includeWatermark }`
- `toJson`/`fromJson` (shared_preferences 저장용)

> 모든 toMap 키는 snake_case(DB 컬럼과 일치). 날짜는 `millisecondsSinceEpoch(int)`.

## 3. 리포지토리 (`lib/core/repositories/`) — 추상 인터페이스

Riverpod provider로 주입받는다. **직접 `...Impl`을 생성하지 말 것.**

### MemberRepository (`memberRepositoryProvider`)
- `Future<List<MemberListItem>> list({String? query, MemberSort sort})`
  - `MemberSort { recentShot, name, registeredAt }`
  - `MemberListItem { Member member, int recordCount, DateTime? lastShotAt }`
- `Future<Member?> getById(String id)`
- `Future<void> insert(Member)` / `update(Member)`
- `Future<void> delete(String id)` — 촬영 기록·사진 행(CASCADE)과 저장소 파일까지 연쇄 삭제

### PhotoRecordRepository (`photoRecordRepositoryProvider`)
- `Future<List<PhotoRecord>> listByMember(String memberId)` (최신 촬영일 먼저)
- `getById`, `insert`, `update`, `delete(id)`(소속 사진 파일+행 삭제)

### BodyPhotoRepository (`bodyPhotoRepositoryProvider`)
- `Future<List<BodyPhoto>> listByRecord(String recordId)`
- `Future<List<BodyPhoto>> listByMemberDirection(String memberId, BodyDirection)` (비교용, 최신 촬영일 먼저)
- `getById`, `insert`, `update`(메타데이터만; 원본 파일 불변), `delete(id)`, `deleteByRecord(recordId)`

## 4. 서비스 (`lib/core/services/`)

### PhotoStorageService (`photoStorageServiceProvider`)
앱 문서 디렉터리 `photos/{memberId}/`에 원본을 **무변형** 저장.
- `Future<String> saveOriginal({memberId, sourcePath, fileName?})` → 저장 경로
- `Future<String> saveBytes({memberId, bytes, fileName})`
- `deleteFile(path)`, `deleteMemberDir(memberId)`, `memberDir(memberId)`
- 동일 파일명 존재 시 `name(1).jpg`로 회피(덮어쓰기 금지).

### GridSettingsService (`gridSettingsServiceProvider`)
shared_preferences 영속화. `load()`, `save(GridSettings)`, `reset()`.

### AppLogger (`appLoggerProvider`, `AppLogger.instance`)
구조화 로그. `info/warn/error/debug(event, context:)` 및
`phase(feature, LogPhase.{start,progress,success,failure}, context:)`.
- `event`는 안정적 키(예: `'member.delete.success'`).
- `context`에는 id·count만. **이름/경로/사진 등 개인정보 금지.**
- 테스트에서 `AppLogger.instance.sink = (entry){...}`로 가로채기 가능.

## 5. 라우팅 (`lib/core/router/`)

`context.goNamed(AppRoutes.x, pathParameters: {...})` / `pushNamed` 사용. **경로 문자열 하드코딩 금지.**
`AppRoutes` 이름과 `AppParams`(memberId/recordId/photoId) 키 사용.

| # | 화면 | AppRoutes 이름 | 경로 | 파라미터 |
|---|------|----------------|------|----------|
| 1 | 앱 시작 | `appStart` | `/` | — |
| 2 | 회원 목록 | `membersList` | `/members` | — |
| 3 | 회원 등록 | `memberAdd` | `/members/new` | — |
| 4 | 회원 상세 | `memberDetail` | `/members/:memberId` | memberId |
| 5 | 회원 수정 | `memberEdit` | `/members/:memberId/edit` | memberId |
| 6 | 촬영 방향 선택 | `captureDirection` | `/members/:memberId/capture` | memberId |
| 7 | 격자 카메라 | `captureCamera` | `/members/:memberId/capture/camera` | memberId |
| 8 | 촬영 결과 확인 | `captureReview` | `/members/:memberId/capture/review` | memberId |
| 9 | 갤러리 등록 | `galleryImport` | `/members/:memberId/import` | memberId |
| 10 | 촬영 기록 상세 | `recordDetail` | `/members/:memberId/records/:recordId` | memberId, recordId |
| 11 | 원본 사진 보기 | `photoView` | `/members/:memberId/records/:recordId/photos/:photoId` | +photoId |
| 12 | 비교 날짜 선택 | `compareDates` | `/members/:memberId/compare` | memberId |
| 13 | 비교 방향 선택 | `compareDirection` | `/members/:memberId/compare/direction` | memberId |
| 14 | 전후 사진 비교 | `compareView` | `/members/:memberId/compare/view` | memberId |
| 15 | 비교 이미지 설정 | `compareExport` | `/members/:memberId/compare/export` | memberId |
| 16 | 앱 설정 | `settings` | `/settings` | — |
| 17 | 앱 잠금 설정 | `appLock` | `/settings/lock` | — |
| 18 | 백업 및 복원 | `backupRestore` | `/settings/backup` | — |
| 19 | 저장 공간 관리 | `storage` | `/settings/storage` | — |
| 20 | 개인정보/이용 안내 | `privacyInfo` | `/settings/privacy` | — |

방향/사진 선택 등 부가 값은 쿼리 파라미터(`AppParams.direction` 등)로 전달한다.
각 화면 파일은 `lib/features/<영역>/`에 placeholder로 이미 존재하며, 워커는 이를
실제 구현으로 교체하되 `static const screenId`와 라우트 연결은 유지한다.

## 6. Semantics + ValueKey 명명 규칙 (RULE.md 1~7)

모든 주요 요소(화면 루트/버튼/입력란/상태 표시/결과 영역)에 **변하지 않는**
식별자를 부여한다. 문구·색상·위치·순서에 의존하지 않는다.

- 화면 루트: `screen.<영역>.<이름>` — 예 `screen.members.list`, `screen.compare.view`
  - `Semantics(identifier: screenId, container: true, label: ...)` + `Scaffold(key: ValueKey(screenId))`
- 조작/결과 요소: `<영역>.<대상>.<종류>` — 예:
  - 버튼 `members.add.button`, `member.delete.button`
  - 입력란 `member.name.field`
  - 상태 표시 `members.list.status`(비동기 상태), 결과 영역 `compare.result.image`
- `GestureDetector`/`CustomPaint`/이미지 버튼 등 커스텀 UI에는 `Semantics`로
  role(button 등)·label·state(enabled/selected/value)·action을 반드시 제공(RULE.md 5).
- AI가 검사할 주요 영역(비교 결과 등)은 별도 식별자로 감싸 영역 단위 캡처가 가능하게 한다(RULE.md 7).

## 7. 비동기 4-상태 UI (RULE.md 6)

단순 로딩 스피너만 두지 말 것. **대기 / 진행 중 / 성공 / 실패**를 UI 계층에서
구분 가능하게 표현한다. Riverpod `AsyncValue`를 쓰되 상태 표시 위젯에
`screen.<x>.status` 식별자를 부여하고, 실패 시 재시도 액션과 에러 메시지를 노출한다.

권장 패턴:
```dart
final async = ref.watch(someProvider);
return async.when(
  data: (v) => _Loaded(v),      // 성공 (+ 빈 상태 구분)
  loading: () => const _Busy(), // 진행 중 (idle과 구분되게 status 식별자 유지)
  error: (e, _) => _Failed(e),  // 실패 + 재시도 버튼
);
```

## 8. 테스트 주입 (RULE.md 8·10)

리포지토리·서비스는 전부 추상 인터페이스이므로 `ProviderScope(overrides:)`로 교체한다.

Fake 주입:
```dart
ProviderScope(
  overrides: [
    memberRepositoryProvider.overrideWithValue(FakeMemberRepository()),
  ],
  child: const MyScreen(),
);
```

실제 DB로 테스트(인메모리 sqflite, `test/core/repositories/member_repository_test.dart` 참고):
```dart
sqfliteFfiInit();
databaseFactory = databaseFactoryFfi;
final db = AppDatabase.forTesting();               // inMemory
final storage = PhotoStorageServiceImpl(rootPath: tempDir.path);
```

랜덤/시간/애니메이션에 의존하지 않게 fixture와 고정 DateTime을 쓴다(RULE.md 10).
