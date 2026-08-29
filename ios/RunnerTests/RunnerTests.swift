import Flutter
import Foundation
import XCTest
@testable import Runner

/// 앱 컨테이너는 iOS 기본값(백업 포함)을 그대로 사용한다.
///
/// iOS는 iCloud 백업과 Quick Start 기기 전송을 나누는 스위치가 없어
/// `isExcludedFromBackup`을 켜면 기기 교체 시 기록이 함께 사라진다.
/// 앱이 이 값을 건드리지 않는지 회귀로 확인한다.
final class RunnerTests: XCTestCase {

  func testAppDoesNotExcludeContainerFromBackup() throws {
    let fileManager = FileManager.default
    let documents = try fileManager.url(
      for: .documentDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )

    let excluded = try documents
      .resourceValues(forKeys: [.isExcludedFromBackupKey])
      .isExcludedFromBackup

    XCTAssertNotEqual(excluded, true)
  }
}
