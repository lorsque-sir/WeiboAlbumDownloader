// 单元测试用例参考
// 当前项目为单一 executableTarget，不支持直接 @testable import。
// 重构为 library + executable 后可取消注释并运行。
//
// import XCTest
// @testable import WeiboAlbumDownloaderLib
//
// final class CronExpressionTests: XCTestCase {
//
//     func testParseValidExpression() {
//         XCTAssertNotNil(CronExpression("14 2 * * *"))
//         XCTAssertNotNil(CronExpression("0 0 1 1 *"))
//         XCTAssertNotNil(CronExpression("*/5 * * * *"))
//         XCTAssertNotNil(CronExpression("0 9-17 * * 1-5"))
//         XCTAssertNotNil(CronExpression("0,30 * * * *"))
//     }
//
//     func testParseInvalidExpression() {
//         XCTAssertNil(CronExpression(""))
//         XCTAssertNil(CronExpression("* * *"))
//         XCTAssertNil(CronExpression("60 * * * *"))
//         XCTAssertNil(CronExpression("* 25 * * *"))
//         XCTAssertNil(CronExpression("a b c d e"))
//     }
//
//     func testFieldStep() {
//         let field = CronField("*/15", range: 0...59)!
//         XCTAssertTrue(field.matches(0))
//         XCTAssertTrue(field.matches(15))
//         XCTAssertTrue(field.matches(30))
//         XCTAssertFalse(field.matches(7))
//     }
//
//     func testFieldRange() {
//         let field = CronField("9-17", range: 0...23)!
//         XCTAssertFalse(field.matches(8))
//         XCTAssertTrue(field.matches(9))
//         XCTAssertTrue(field.matches(17))
//         XCTAssertFalse(field.matches(18))
//     }
//
//     func testNextDateEveryDay() {
//         let cron = CronExpression("14 2 * * *")!
//         let calendar = Calendar.current
//         let start = calendar.date(from: DateComponents(year: 2024, month: 6, day: 1, hour: 0, minute: 0))!
//         let next = cron.nextDate(after: start)
//         XCTAssertNotNil(next)
//         let c = calendar.dateComponents([.hour, .minute], from: next!)
//         XCTAssertEqual(c.hour, 2)
//         XCTAssertEqual(c.minute, 14)
//     }
//
//     func testNextDateEvery5Minutes() {
//         let cron = CronExpression("*/5 * * * *")!
//         let calendar = Calendar.current
//         let start = calendar.date(from: DateComponents(year: 2024, month: 6, day: 1, hour: 10, minute: 7))!
//         let next = cron.nextDate(after: start)
//         XCTAssertNotNil(next)
//         let c = calendar.dateComponents([.hour, .minute], from: next!)
//         XCTAssertEqual(c.hour, 10)
//         XCTAssertEqual(c.minute, 10)
//     }
// }
