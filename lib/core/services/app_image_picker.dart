import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_logger.dart';

/// image_picker의 플랫폼 채널을 감싸는 테스트 교체 지점.
abstract class AppImagePicker {
  bool get supportsLostDataRecovery;

  Future<XFile?> pickImage({required ImageSource source});

  Future<List<XFile>> pickMultiImage();

  Future<LostDataResponse> retrieveLostData();
}

class AppImagePickerImpl implements AppImagePicker {
  final ImagePicker _picker;

  AppImagePickerImpl({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  @override
  bool get supportsLostDataRecovery => Platform.isAndroid;

  @override
  Future<XFile?> pickImage({required ImageSource source}) {
    return _picker.pickImage(source: source);
  }

  @override
  Future<List<XFile>> pickMultiImage() {
    return _picker.pickMultiImage();
  }

  @override
  Future<LostDataResponse> retrieveLostData() {
    return _picker.retrieveLostData();
  }
}

/// Android Activity가 사진 선택 중 종료되었을 때 결과를 돌려받을 기능 구분.
enum ImagePickerOperation {
  galleryImport,
  newMemberAvatar,
  memberAvatar,
  photoReplacement,
  studioLogo,
}

/// picker 실행 전에 남기는 비식별 작업 문맥.
///
/// 화면 문구나 이름 같은 PII 대신 소유관계 확인에 필요한 ID만 저장한다.
class ImagePickerRequestContext {
  final ImagePickerOperation operation;
  final String? memberId;
  final String? recordId;
  final String? photoId;

  const ImagePickerRequestContext._({
    required this.operation,
    this.memberId,
    this.recordId,
    this.photoId,
  });

  factory ImagePickerRequestContext.galleryImport(String memberId) {
    return ImagePickerRequestContext._(
      operation: ImagePickerOperation.galleryImport,
      memberId: _requiredId(memberId, 'memberId'),
    );
  }

  factory ImagePickerRequestContext.memberAvatar(String memberId) {
    return ImagePickerRequestContext._(
      operation: ImagePickerOperation.memberAvatar,
      memberId: _requiredId(memberId, 'memberId'),
    );
  }

  factory ImagePickerRequestContext.newMemberAvatar() {
    return const ImagePickerRequestContext._(
      operation: ImagePickerOperation.newMemberAvatar,
    );
  }

  factory ImagePickerRequestContext.photoReplacement({
    required String memberId,
    required String recordId,
    required String photoId,
  }) {
    return ImagePickerRequestContext._(
      operation: ImagePickerOperation.photoReplacement,
      memberId: _requiredId(memberId, 'memberId'),
      recordId: _requiredId(recordId, 'recordId'),
      photoId: _requiredId(photoId, 'photoId'),
    );
  }

  factory ImagePickerRequestContext.studioLogo() {
    return const ImagePickerRequestContext._(
      operation: ImagePickerOperation.studioLogo,
    );
  }

  factory ImagePickerRequestContext.fromJson(Map<String, Object?> json) {
    if (json.keys.any(
      (key) =>
          !const {'operation', 'memberId', 'recordId', 'photoId'}.contains(key),
    )) {
      throw const FormatException('알 수 없는 picker 문맥 필드입니다.');
    }
    final operationName = json['operation'];
    if (operationName is! String) {
      throw const FormatException('picker 작업 종류가 없습니다.');
    }
    final operation = ImagePickerOperation.values
        .where((value) => value.name == operationName)
        .firstOrNull;
    if (operation == null) {
      throw const FormatException('알 수 없는 picker 작업 종류입니다.');
    }

    String? optionalId(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('$key 값이 올바르지 않습니다.');
      }
      return value;
    }

    final memberId = optionalId('memberId');
    final recordId = optionalId('recordId');
    final photoId = optionalId('photoId');
    switch (operation) {
      case ImagePickerOperation.galleryImport:
      case ImagePickerOperation.memberAvatar:
        if (memberId == null || recordId != null || photoId != null) {
          throw const FormatException('회원 picker 문맥이 올바르지 않습니다.');
        }
      case ImagePickerOperation.newMemberAvatar:
        if (memberId != null || recordId != null || photoId != null) {
          throw const FormatException('신규 회원 picker 문맥이 올바르지 않습니다.');
        }
      case ImagePickerOperation.photoReplacement:
        if (memberId == null || recordId == null || photoId == null) {
          throw const FormatException('사진 교체 picker 문맥이 올바르지 않습니다.');
        }
      case ImagePickerOperation.studioLogo:
        if (memberId != null || recordId != null || photoId != null) {
          throw const FormatException('로고 picker 문맥이 올바르지 않습니다.');
        }
    }
    return ImagePickerRequestContext._(
      operation: operation,
      memberId: memberId,
      recordId: recordId,
      photoId: photoId,
    );
  }

  Map<String, Object?> toJson() => {
    'operation': operation.name,
    if (memberId != null) 'memberId': memberId,
    if (recordId != null) 'recordId': recordId,
    if (photoId != null) 'photoId': photoId,
  };

  @override
  bool operator ==(Object other) {
    return other is ImagePickerRequestContext &&
        operation == other.operation &&
        memberId == other.memberId &&
        recordId == other.recordId &&
        photoId == other.photoId;
  }

  @override
  int get hashCode => Object.hash(operation, memberId, recordId, photoId);

  static String _requiredId(String value, String name) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, name, '비어 있지 않아야 합니다.');
    }
    return value;
  }
}

/// 복구 결과와 그 결과를 받을 수 있는 정확한 화면 문맥.
class RecoveredImagePickerSelection {
  final ImagePickerRequestContext context;
  final List<XFile> files;

  RecoveredImagePickerSelection({
    required this.context,
    required List<XFile> files,
  }) : files = List<XFile>.unmodifiable(files) {
    if (files.isEmpty || files.any((file) => file.path.trim().isEmpty)) {
      throw ArgumentError.value(files, 'files', '복구할 파일 경로가 필요합니다.');
    }
  }

  XFile? get lastFile => files.isEmpty ? null : files.last;

  factory RecoveredImagePickerSelection.fromJson(Map<String, Object?> json) {
    if (json.keys.any((key) => !const {'context', 'filePaths'}.contains(key))) {
      throw const FormatException('알 수 없는 picker 복구 필드입니다.');
    }
    final rawContext = json['context'];
    final rawPaths = json['filePaths'];
    if (rawContext is! Map<String, Object?> || rawPaths is! List<Object?>) {
      throw const FormatException('picker 복구 값이 올바르지 않습니다.');
    }
    final paths = rawPaths.whereType<String>().toList(growable: false);
    if (paths.length != rawPaths.length ||
        paths.isEmpty ||
        paths.any((path) => path.trim().isEmpty)) {
      throw const FormatException('picker 복구 파일 경로가 올바르지 않습니다.');
    }
    return RecoveredImagePickerSelection(
      context: ImagePickerRequestContext.fromJson(rawContext),
      files: paths.map((path) => XFile(path)).toList(growable: false),
    );
  }

  Map<String, Object?> toJson() => {
    'context': context.toJson(),
    'filePaths': files.map((file) => file.path).toList(growable: false),
  };
}

abstract class ImagePickerRequestStore {
  Future<ImagePickerRequestContext?> load();

  Future<void> save(ImagePickerRequestContext context);

  Future<void> clearIfMatches(ImagePickerRequestContext context);

  Future<void> clear();
}

abstract class ImagePickerRecoveryStore {
  Future<RecoveredImagePickerSelection?> loadRecovered();

  Future<void> saveRecovered(RecoveredImagePickerSelection selection);

  Future<void> clearRecoveredIfMatches(ImagePickerRequestContext context);

  Future<void> clearRecovered();
}

class _VolatileImagePickerRecoveryStore implements ImagePickerRecoveryStore {
  RecoveredImagePickerSelection? _selection;

  @override
  Future<void> clearRecovered() async => _selection = null;

  @override
  Future<void> clearRecoveredIfMatches(
    ImagePickerRequestContext context,
  ) async {
    if (_selection?.context == context) _selection = null;
  }

  @override
  Future<RecoveredImagePickerSelection?> loadRecovered() async => _selection;

  @override
  Future<void> saveRecovered(RecoveredImagePickerSelection selection) async {
    _selection = selection;
  }
}

class SharedPreferencesImagePickerRequestStore
    implements ImagePickerRequestStore, ImagePickerRecoveryStore {
  static const _pendingKey = 'pending_image_picker_request_v1';
  static const _recoveredKey = 'recovered_image_picker_selection_v1';

  @override
  Future<ImagePickerRequestContext?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final source = preferences.getString(_pendingKey);
    if (source == null) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('picker 문맥 JSON이 객체가 아닙니다.');
      }
      return ImagePickerRequestContext.fromJson(decoded);
    } catch (_) {
      await preferences.remove(_pendingKey);
      return null;
    }
  }

  @override
  Future<void> save(ImagePickerRequestContext context) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(_pendingKey, jsonEncode(context));
    if (!saved) {
      throw StateError('picker 작업 문맥을 저장하지 못했습니다.');
    }
  }

  @override
  Future<void> clearIfMatches(ImagePickerRequestContext context) async {
    final current = await load();
    if (current == context) {
      await clear();
    }
  }

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    final removed = await preferences.remove(_pendingKey);
    if (!removed && preferences.containsKey(_pendingKey)) {
      throw StateError('picker 작업 문맥을 정리하지 못했습니다.');
    }
  }

  @override
  Future<RecoveredImagePickerSelection?> loadRecovered() async {
    final preferences = await SharedPreferences.getInstance();
    final source = preferences.getString(_recoveredKey);
    if (source == null) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('picker 복구 JSON이 객체가 아닙니다.');
      }
      return RecoveredImagePickerSelection.fromJson(decoded);
    } catch (_) {
      await preferences.remove(_recoveredKey);
      return null;
    }
  }

  @override
  Future<void> saveRecovered(RecoveredImagePickerSelection selection) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _recoveredKey,
      jsonEncode(selection.toJson()),
    );
    if (!saved) {
      throw StateError('picker 복구 결과를 저장하지 못했습니다.');
    }
  }

  @override
  Future<void> clearRecoveredIfMatches(
    ImagePickerRequestContext context,
  ) async {
    final current = await loadRecovered();
    if (current?.context == context) {
      await clearRecovered();
    }
  }

  @override
  Future<void> clearRecovered() async {
    final preferences = await SharedPreferences.getInstance();
    final removed = await preferences.remove(_recoveredKey);
    if (!removed && preferences.containsKey(_recoveredKey)) {
      throw StateError('picker 복구 결과를 정리하지 못했습니다.');
    }
  }
}

/// 앱 전역에서 Android 유실 결과를 한 번만 회수하고 정확한 화면에 전달한다.
class AppImagePickerCoordinator
    extends StateNotifier<RecoveredImagePickerSelection?> {
  final AppImagePicker _picker;
  final ImagePickerRequestStore _requestStore;
  final ImagePickerRecoveryStore _recoveryStore;
  final AppLogger _logger;

  Future<void>? _initialization;
  bool _initialized = false;

  AppImagePickerCoordinator({
    required AppImagePicker picker,
    required ImagePickerRequestStore requestStore,
    ImagePickerRecoveryStore? recoveryStore,
    AppLogger? logger,
  }) : _picker = picker,
       _requestStore = requestStore,
       _recoveryStore =
           recoveryStore ??
           (requestStore is ImagePickerRecoveryStore
               ? requestStore as ImagePickerRecoveryStore
               : _VolatileImagePickerRecoveryStore()),
       _logger = logger ?? AppLogger.instance,
       super(null);

  /// 여러 화면이 동시에 초기화를 요구해도 동일 Future를 공유한다.
  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    final running = _initialization;
    if (running != null) return running;

    late final Future<void> initialization;
    initialization = _recoverLostDataOnce()
        .then((completed) {
          if (!completed) {
            throw StateError('사진 선택 복구 초기화를 완료하지 못했습니다.');
          }
          _initialized = true;
        })
        .whenComplete(() {
          if (identical(_initialization, initialization)) {
            _initialization = null;
          }
        });
    _initialization = initialization;
    return initialization;
  }

  Future<XFile?> pickImage({
    required ImagePickerRequestContext context,
    required ImageSource source,
  }) async {
    await initialize();
    await _prepareForNewRequest(context);
    await _requestStore.save(context);
    try {
      return await _picker.pickImage(source: source);
    } finally {
      await _clearRequestAfterPicker(context);
    }
  }

  Future<List<XFile>> pickMultiImage({
    required ImagePickerRequestContext context,
  }) async {
    await initialize();
    await _prepareForNewRequest(context);
    await _requestStore.save(context);
    try {
      return await _picker.pickMultiImage();
    } finally {
      await _clearRequestAfterPicker(context);
    }
  }

  /// [context]가 완전히 같은 화면만 결과를 확인할 수 있다.
  ///
  /// 화면 반영이 끝나기 전 프로세스가 다시 종료되어도 복구할 수 있도록 이 호출은
  /// 결과를 지우지 않는다. 반영 성공 뒤 [acknowledgeRecovered]를 호출해야 한다.
  RecoveredImagePickerSelection? recoveredFor(
    ImagePickerRequestContext context,
  ) {
    final recovered = state;
    if (recovered == null || recovered.context != context) return null;
    return recovered;
  }

  Future<void> acknowledgeRecovered(ImagePickerRequestContext context) async {
    final recovered = state;
    if (recovered == null || recovered.context != context) return;
    try {
      await _recoveryStore.clearRecoveredIfMatches(context);
      await _requestStore.clearIfMatches(context);
      if (state?.context == context) state = null;
    } catch (_) {
      _logger.warn('imagePicker.recovery.acknowledge.failure');
      rethrow;
    }
  }

  Future<bool> _recoverLostDataOnce() async {
    if (!_picker.supportsLostDataRecovery) {
      try {
        await _requestStore.clear();
        await _recoveryStore.clearRecovered();
      } catch (_) {
        _logger.warn('imagePicker.request.cleanup.failure');
      }
      return true;
    }

    try {
      final persisted = await _recoveryStore.loadRecovered();
      if (persisted != null) {
        final accessible = await _allRecoveredFilesExist(persisted);
        if (!accessible) {
          await _recoveryStore.clearRecoveredIfMatches(persisted.context);
          await _requestStore.clearIfMatches(persisted.context);
          _logger.warn('imagePicker.recovery.missingFiles');
          return true;
        }
        state = persisted;
        return true;
      }
    } catch (_) {
      _logger.warn('imagePicker.recovery.load.failure');
      return false;
    }

    ImagePickerRequestContext? request;
    try {
      request = await _requestStore.load();
    } catch (_) {
      _logger.warn('imagePicker.request.load.failure');
      return false;
    }
    try {
      final response = await _picker.retrieveLostData();
      final recoveredFiles = response.files;
      final files = recoveredFiles != null && recoveredFiles.isNotEmpty
          ? recoveredFiles
          : (response.file == null ? const <XFile>[] : <XFile>[response.file!]);
      if (request != null && files.isNotEmpty) {
        final recovered = RecoveredImagePickerSelection(
          context: request,
          files: files,
        );
        await _recoveryStore.saveRecovered(recovered);
        state = recovered;
        _logger.info(
          'imagePicker.recovery.success',
          context: {'operation': request.operation.name, 'count': files.length},
        );
      } else if (!response.isEmpty) {
        _logger.warn('imagePicker.recovery.unmatched');
      }
      if (files.isEmpty && request != null) {
        await _clearRequestAfterPicker(request);
      }
      return true;
    } catch (_) {
      _logger.phase('imagePicker.recovery', LogPhase.failure);
      // 플랫폼 회수가 일시적으로 실패하면 pending 문맥을 보존한다. initialize를
      // 다시 호출하면 같은 프로세스에서도 재시도할 수 있다.
      return false;
    }
  }

  Future<void> _prepareForNewRequest(ImagePickerRequestContext context) async {
    final recovered = state;
    if (recovered == null) return;
    if (recovered.context == context) {
      throw StateError('이전 사진 선택 복구 결과를 먼저 확인해야 합니다.');
    }
    try {
      await _recoveryStore.clearRecoveredIfMatches(recovered.context);
      await _requestStore.clearIfMatches(recovered.context);
      if (identical(state, recovered)) state = null;
      _logger.info(
        'imagePicker.recovery.superseded',
        context: {
          'previousOperation': recovered.context.operation.name,
          'nextOperation': context.operation.name,
        },
      );
    } catch (_) {
      _logger.warn('imagePicker.recovery.supersede.failure');
      rethrow;
    }
  }

  Future<bool> _allRecoveredFilesExist(
    RecoveredImagePickerSelection selection,
  ) async {
    for (final file in selection.files) {
      try {
        if (!await File(file.path).exists()) return false;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  Future<void> _clearRequestAfterPicker(
    ImagePickerRequestContext context,
  ) async {
    try {
      await _requestStore.clearIfMatches(context);
    } catch (_) {
      _logger.warn('imagePicker.request.cleanup.failure');
    }
  }
}

final appImagePickerProvider = Provider<AppImagePicker>((ref) {
  return AppImagePickerImpl();
});

final imagePickerRequestStoreProvider = Provider<ImagePickerRequestStore>((
  ref,
) {
  return SharedPreferencesImagePickerRequestStore();
});

final appImagePickerCoordinatorProvider =
    StateNotifierProvider<
      AppImagePickerCoordinator,
      RecoveredImagePickerSelection?
    >((ref) {
      final coordinator = AppImagePickerCoordinator(
        picker: ref.watch(appImagePickerProvider),
        requestStore: ref.watch(imagePickerRequestStoreProvider),
      );
      unawaited(() async {
        try {
          await coordinator.initialize();
        } catch (_) {
          // pending 문맥은 보존된다. 다음 화면/선택 요청이 initialize를 재시도한다.
        }
      }());
      return coordinator;
    });
