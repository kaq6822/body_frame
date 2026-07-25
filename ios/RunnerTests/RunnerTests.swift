import Flutter
import Foundation
import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {

  func testSensitiveDataProtectionAppliesRecursivelyWithoutFollowingSymlinks() throws {
    let fileManager = FileManager.default
    let testRoot = fileManager.temporaryDirectory
      .appendingPathComponent("body-frame-protection-\(UUID().uuidString)")
    let protectedRoot = testRoot.appendingPathComponent("Documents")
    let nestedDirectory = protectedRoot.appendingPathComponent("members/member-1")
    let nestedFile = nestedDirectory.appendingPathComponent("front.jpg")
    let externalRoot = testRoot.appendingPathComponent("outside")
    let externalFile = externalRoot.appendingPathComponent("must-remain-unchanged.db")
    let symlink = protectedRoot.appendingPathComponent("outside-link")

    defer {
      try? fileManager.removeItem(at: testRoot)
    }

    try fileManager.createDirectory(
      at: nestedDirectory,
      withIntermediateDirectories: true
    )
    try fileManager.createDirectory(
      at: externalRoot,
      withIntermediateDirectories: true
    )
    try Data("photo".utf8).write(to: nestedFile)
    try Data("database".utf8).write(to: externalFile)
    try fileManager.createSymbolicLink(
      at: symlink,
      withDestinationURL: externalRoot
    )

    var externalValues = URLResourceValues()
    externalValues.isExcludedFromBackup = false
    var mutableExternalFile = externalFile
    try mutableExternalFile.setResourceValues(externalValues)

    SensitiveDataProtector(fileManager: fileManager)
      .protectRecursively(at: protectedRoot)

    XCTAssertEqual(backupExclusion(of: protectedRoot), true)
    XCTAssertEqual(backupExclusion(of: nestedDirectory), true)
    XCTAssertEqual(backupExclusion(of: nestedFile), true)
    XCTAssertEqual(backupExclusion(of: externalFile), false)

    let attributes = try fileManager.attributesOfItem(atPath: nestedFile.path)
    if let protection = attributes[.protectionKey] as? FileProtectionType {
      XCTAssertEqual(protection, .complete)
    }
  }

  private func backupExclusion(of url: URL) -> Bool? {
    try? url.resourceValues(forKeys: [.isExcludedFromBackupKey])
      .isExcludedFromBackup
  }
}
