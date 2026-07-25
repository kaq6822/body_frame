import Flutter
import UIKit

/// 앱 컨테이너의 민감정보 디렉터리를 시스템 백업에서 제외하고 완전 파일 보호한다.
///
/// 루트 속성은 Flutter 엔진 시작 전에 적용해 새 파일이 보호 속성을 상속하게 한다.
/// 기존 항목은 앱 시작을 막지 않도록 백그라운드에서 메타데이터만 순회하며,
/// 심볼릭 링크는 대상과 하위 항목 모두 건드리지 않는다.
final class SensitiveDataProtector {
  private let fileManager: FileManager
  private let queue: DispatchQueue

  init(
    fileManager: FileManager = .default,
    queue: DispatchQueue = DispatchQueue(
      label: "com.bodyframe.sensitive-data-protection",
      qos: .utility
    )
  ) {
    self.fileManager = fileManager
    self.queue = queue
  }

  func protectDefaultLocations() {
    let roots = [
      protectedDirectory(.documentDirectory),
      protectedDirectory(.applicationSupportDirectory),
    ].compactMap { $0 }

    for root in roots {
      protectItem(at: root)
    }
    queue.async { [self] in
      for root in roots {
        protectExistingItems(below: root)
      }
    }
  }

  /// 테스트에서는 임시 디렉터리를 동기적으로 검증할 수 있게 분리한다.
  func protectRecursively(at root: URL) {
    protectItem(at: root)
    protectExistingItems(below: root)
  }

  private func protectedDirectory(_ directory: FileManager.SearchPathDirectory) -> URL? {
    try? fileManager.url(
      for: directory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
  }

  private func protectExistingItems(below root: URL) {
    guard let enumerator = fileManager.enumerator(
      at: root,
      includingPropertiesForKeys: [.isSymbolicLinkKey],
      options: [.skipsPackageDescendants],
      errorHandler: { _, _ in true }
    ) else {
      return
    }

    for case let itemURL as URL in enumerator {
      let values = try? itemURL.resourceValues(forKeys: [.isSymbolicLinkKey])
      if values?.isSymbolicLink == true {
        continue
      }
      protectItem(at: itemURL)
    }
  }

  private func protectItem(at url: URL) {
    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    var mutableURL = url
    try? mutableURL.setResourceValues(resourceValues)
    try? fileManager.setAttributes(
      [.protectionKey: FileProtectionType.complete],
      ofItemAtPath: url.path
    )
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let sensitiveDataProtector = SensitiveDataProtector()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    sensitiveDataProtector.protectDefaultLocations()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
