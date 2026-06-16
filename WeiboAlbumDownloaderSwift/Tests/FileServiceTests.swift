// 单元测试用例参考
// 当前项目为单一 executableTarget，不支持直接 @testable import。
// 重构为 library + executable 后可取消注释并运行。
//
// import XCTest
// @testable import WeiboAlbumDownloaderLib
//
// final class FileServiceTests: XCTestCase {
//
//     private var tempDir: URL!
//     private var fileService: FileService!
//
//     override func setUp() {
//         super.setUp()
//         tempDir = FileManager.default.temporaryDirectory
//             .appendingPathComponent("WeiboTests-\(UUID().uuidString)")
//         try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
//         fileService = FileService(baseDirectory: tempDir)
//     }
//
//     override func tearDown() {
//         try? FileManager.default.removeItem(at: tempDir)
//         super.tearDown()
//     }
//
//     func testCleanFileName() {
//         XCTAssertEqual(fileService.cleanFileName("photo.jpg"), "photo.jpg")
//         XCTAssertEqual(fileService.cleanFileName("a/b\\c:d.jpg"), "abcd.jpg")
//     }
//
//     func testCleanFileNameTruncation() {
//         let longName = String(repeating: "a", count: 250) + ".jpg"
//         let cleaned = fileService.cleanFileName(longName)
//         XCTAssertLessThanOrEqual(cleaned.count, 204)
//         XCTAssertTrue(cleaned.hasSuffix(".jpg"))
//     }
//
//     func testUserDirectoryWithNickname() {
//         let dir = fileService.userDirectory(uid: "12345", nickname: "TestUser")
//         XCTAssertTrue(dir.lastPathComponent.contains("12345"))
//         XCTAssertTrue(dir.lastPathComponent.contains("TestUser"))
//     }
//
//     func testResolveFileNotExists() {
//         let dir = fileService.userDirectory(uid: "test2", nickname: nil)
//         let (exists, destination) = fileService.resolveFile(directory: dir, fileName: "new.jpg")
//         XCTAssertFalse(exists)
//         XCTAssertEqual(destination.lastPathComponent, "new.jpg")
//     }
//
//     func testSetFileTimestamp() throws {
//         let dir = fileService.userDirectory(uid: "ts", nickname: nil)
//         let file = dir.appendingPathComponent("timestamp-test.txt")
//         try "test".write(to: file, atomically: true, encoding: .utf8)
//         let targetDate = Date(timeIntervalSince1970: 1609459200)
//         try fileService.setFileTimestamp(file, date: targetDate)
//         let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
//         let modDate = attrs[.modificationDate] as? Date
//         XCTAssertNotNil(modDate)
//         XCTAssertEqual(modDate!.timeIntervalSince1970, targetDate.timeIntervalSince1970, accuracy: 1.0)
//     }
// }
