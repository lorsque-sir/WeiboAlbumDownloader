import Foundation
import SwiftUI

// MARK: - 设置视图模型

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var showCnCookieSheet = false
    @Published var showComCookieSheet = false
    @Published var uidListEntries: [UIDEntry] = []
    @Published var newUIDText: String = ""
    @Published var cnCookieStatus: CookieStatus = .unknown
    @Published var comCookieStatus: CookieStatus = .unknown

    enum CookieStatus: Equatable {
        case unknown, checking, valid, invalid(String)
    }

    struct UIDEntry: Identifiable {
        let id = UUID()
        var uid: String
        var nickname: String?
    }

    init() {
        self.settings = AppSettings.load()
        loadUIDList()
    }

    func reload() {
        settings = AppSettings.load()
        loadUIDList()
    }

    func save() {
        if settings.enableDatetimeRange && settings.startDateTime == nil {
            return
        }
        try? settings.save()
        saveUIDList()
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    // MARK: - Cookie 管理

    func setCnCookie(_ cookie: String) {
        CookieService.saveCnCookie(cookie)
        cnCookieStatus = .unknown
        objectWillChange.send()
    }

    func setComCookie(_ cookie: String) {
        CookieService.saveComCookie(cookie)
        comCookieStatus = .unknown
        objectWillChange.send()
    }

    var hasCnCookie: Bool {
        !(CookieService.loadCnCookie() ?? "").isEmpty
    }

    var hasComCookie: Bool {
        !(CookieService.loadComCookie() ?? "").isEmpty
    }

    var cnCookieText: String {
        get { CookieService.loadCnCookie() ?? "" }
        set {
            if newValue.isEmpty {
                CookieService.saveCnCookie("")
            } else {
                CookieService.saveCnCookie(newValue)
            }
            cnCookieStatus = .unknown
            objectWillChange.send()
        }
    }

    var comCookieText: String {
        get { CookieService.loadComCookie() ?? "" }
        set {
            if newValue.isEmpty {
                CookieService.saveComCookie("")
            } else {
                CookieService.saveComCookie(newValue)
            }
            comCookieStatus = .unknown
            objectWillChange.send()
        }
    }

    /// 检测 Cookie 是否仍然有效
    func checkCookieValidity() {
        if hasCnCookie {
            cnCookieStatus = .checking
            Task {
                let valid = await verifyCookie(
                    cookie: CookieService.loadCnCookie() ?? "",
                    testURL: URL(string: "https://m.weibo.cn/api/config")!
                )
                cnCookieStatus = valid ? .valid : .invalid("Cookie 已失效")
            }
        }
        if hasComCookie {
            comCookieStatus = .checking
            Task {
                let valid = await verifyCookie(
                    cookie: CookieService.loadComCookie() ?? "",
                    testURL: URL(string: "https://weibo.com/ajax/setting/getSetting")!
                )
                comCookieStatus = valid ? .valid : .invalid("Cookie 已失效")
            }
        }
    }

    private func verifyCookie(cookie: String, testURL: URL) async -> Bool {
        var request = URLRequest(url: testURL)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return false }
            if let body = String(data: data, encoding: .utf8),
               body.contains("<title>登录 - 微博</title>") {
                return false
            }
            return true
        } catch {
            return false
        }
    }

    var crontabDescription: String {
        guard let cron = settings.crontab, !cron.isEmpty else { return "未设置" }
        return "Cron: \(cron)"
    }

    // MARK: - UID 列表管理

    private static var uidListURL: URL {
        AppSettings.settingsURL
            .deletingLastPathComponent()
            .appendingPathComponent("uidList.txt")
    }

    func loadUIDList() {
        let url = Self.uidListURL
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            uidListEntries = []
            return
        }
        uidListEntries = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") }
            .map { line in
                let parts = line.components(separatedBy: ",")
                let uid = parts[0].trimmingCharacters(in: .whitespaces)
                let nick = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil
                return UIDEntry(uid: uid, nickname: nick)
            }
    }

    func addUID() {
        let trimmed = newUIDText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let parts = trimmed.components(separatedBy: ",")
        let uid = parts[0].trimmingCharacters(in: .whitespaces)
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty }
            .first ?? ""
        guard !uid.isEmpty else { return }
        guard !uidListEntries.contains(where: { $0.uid == uid }) else { return }

        let nick = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil
        uidListEntries.append(UIDEntry(uid: uid, nickname: nick))
        newUIDText = ""
    }

    func removeUID(at offsets: IndexSet) {
        uidListEntries.remove(atOffsets: offsets)
    }

    func saveUIDList() {
        let url = Self.uidListURL
        var lines = ["//可以是多用户，换行隔开。", "//行内用英文逗号隔开，用户id(必填),用户名(可选)"]
        for entry in uidListEntries {
            if let nick = entry.nickname, !nick.isEmpty {
                lines.append("\(entry.uid),\(nick)")
            } else {
                lines.append(entry.uid)
            }
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
