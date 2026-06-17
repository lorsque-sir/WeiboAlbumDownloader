import SwiftUI

// MARK: - 设置界面

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var saveError: String?
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            TabView(selection: $selectedTab) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        dataSourceSection
                        cookieSection
                    }
                    .padding(20)
                }
                .tabItem { Label("数据源", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(0)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        downloadOptionsSection
                        uidListSection
                    }
                    .padding(20)
                }
                .tabItem { Label("下载", systemImage: "arrow.down.doc.fill") }
                .tag(1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        scheduleSection
                        notificationSection
                    }
                    .padding(20)
                }
                .tabItem { Label("自动化", systemImage: "clock.fill") }
                .tag(2)
            }
        }
    }

    // MARK: - 顶部栏

    private var headerBar: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                Text("设置")
                    .font(.title2.bold())
            }

            Spacer()

            if let error = saveError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }

            Button("完成") {
                if validateAndSave() {
                    dismiss()
                }
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .animation(.easeInOut(duration: 0.2), value: saveError)
    }

    private func validateAndSave() -> Bool {
        if viewModel.settings.enableDatetimeRange && viewModel.settings.startDateTime == nil {
            saveError = "请设置起始日期"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                saveError = nil
            }
            return false
        }
        viewModel.save()
        return true
    }

    // MARK: - 数据源

    private var dataSourceSection: some View {
        @Bindable var vm = viewModel
        return SettingsSection(title: "数据源", icon: "antenna.radiowaves.left.and.right", iconColor: .blue) {
            Picker("数据源", selection: $vm.settings.dataSource) {
                ForEach(WeiboDataSource.allCases) { source in
                    Text(source.displayName).tag(source)
                }
            }
            .pickerStyle(.segmented)

            Label(viewModel.settings.dataSource.description, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Cookie

    private var cookieSection: some View {
        @Bindable var vm = viewModel
        return SettingsSection(title: "Cookie 配置", icon: "key.fill", iconColor: .orange) {
            cookieRow(
                domain: "weibo.cn / m.weibo.cn",
                isConfigured: viewModel.hasCnCookie,
                status: viewModel.cnCookieStatus,
                cookieText: $vm.cnCookieValue,
                onScan: { viewModel.showCnCookieSheet = true }
            )
            .sheet(isPresented: $vm.showCnCookieSheet) {
                CookieWebView(
                    dataSource: .weiboCnMobile,
                    onCookieObtained: { cookie in
                        viewModel.setCnCookie(cookie)
                        viewModel.showCnCookieSheet = false
                    }
                )
                .frame(minWidth: 450, minHeight: 550)
            }

            Divider()

            cookieRow(
                domain: "weibo.com",
                isConfigured: viewModel.hasComCookie,
                status: viewModel.comCookieStatus,
                cookieText: $vm.comCookieValue,
                onScan: { viewModel.showComCookieSheet = true }
            )
            .sheet(isPresented: $vm.showComCookieSheet) {
                CookieWebView(
                    dataSource: .weiboCom1,
                    onCookieObtained: { cookie in
                        viewModel.setComCookie(cookie)
                        viewModel.showComCookieSheet = false
                    }
                )
                .frame(minWidth: 450, minHeight: 550)
            }

            Divider()

            Button {
                viewModel.checkCookieValidity()
            } label: {
                Label("检测 Cookie 有效性", systemImage: "checkmark.shield")
                    .font(.system(size: 12))
            }
        }
    }

    private func cookieRow(
        domain: String,
        isConfigured: Bool,
        status: SettingsViewModel.CookieStatus,
        cookieText: Binding<String>,
        onScan: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(domain)
                        .font(.subheadline.bold())

                    HStack(spacing: 4) {
                        cookieStatusIndicator(isConfigured: isConfigured, status: status)
                    }
                }
                Spacer()
                Button {
                    onScan()
                } label: {
                    Label("扫码获取", systemImage: "qrcode.viewfinder")
                        .font(.system(size: 12))
                }
            }

            TextField("或手动粘贴 Cookie", text: cookieText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
        }
    }

    @ViewBuilder
    private func cookieStatusIndicator(
        isConfigured: Bool,
        status: SettingsViewModel.CookieStatus
    ) -> some View {
        switch status {
        case .checking:
            ProgressView()
                .controlSize(.mini)
            Text("检测中...")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .valid:
            Circle().fill(.green).frame(width: 6, height: 6)
            Text("有效")
                .font(.caption)
                .foregroundStyle(.green)
        case .invalid(let msg):
            Circle().fill(.red).frame(width: 6, height: 6)
            Text(msg)
                .font(.caption)
                .foregroundStyle(.red)
        case .unknown:
            Circle()
                .fill(isConfigured ? .green : .red)
                .frame(width: 6, height: 6)
            Text(isConfigured ? "已配置" : "未配置")
                .font(.caption)
                .foregroundStyle(isConfigured ? .green : .red)
        }
    }

    // MARK: - 下载选项

    private var downloadOptionsSection: some View {
        @Bindable var vm = viewModel
        return SettingsSection(title: "下载选项", icon: "arrow.down.doc.fill", iconColor: .green) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("显示头像", isOn: $vm.settings.showHeadImage)
                Toggle("下载视频", isOn: $vm.settings.enableDownloadVideo)
                Toggle("下载 LivePhoto", isOn: $vm.settings.enableDownloadLivePhoto)
                Toggle("短文件名 (仅日期+编号)", isOn: $vm.settings.enableShortenName)
            }
            .font(.system(size: 13))

            Divider()

            HStack {
                Label("智能跳过阈值", systemImage: "forward.fill")
                    .font(.system(size: 13))
                Spacer()
                TextField("", value: $vm.settings.countDownloadedSkipToNextUser, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .multilineTextAlignment(.center)
                    .onChange(of: viewModel.settings.countDownloadedSkipToNextUser) { _, newVal in
                        viewModel.settings.countDownloadedSkipToNextUser = max(1, min(999, newVal))
                    }
                Text("个已存在文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("同时下载数", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 13))
                Spacer()
                Picker("", selection: $vm.settings.maxConcurrentDownloads) {
                    Text("1").tag(1)
                    Text("3").tag(3)
                    Text("5").tag(5)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            HStack {
                Label("反爬延迟 (毫秒)", systemImage: "timer")
                    .font(.system(size: 13))
                Spacer()
                TextField("", value: $vm.settings.antiCrawlMinDelayMs, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .multilineTextAlignment(.center)
                Text("~")
                    .foregroundStyle(.secondary)
                TextField("", value: $vm.settings.antiCrawlMaxDelayMs, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .multilineTextAlignment(.center)
            }

            Divider()

            Toggle("时间范围过滤", isOn: $vm.settings.enableDatetimeRange)
                .font(.system(size: 13))

            if viewModel.settings.enableDatetimeRange {
                DatePicker(
                    "起始日期",
                    selection: Binding(
                        get: { viewModel.settings.startDateTime ?? Date() },
                        set: { viewModel.settings.startDateTime = $0 }
                    ),
                    displayedComponents: .date
                )
                .font(.system(size: 13))
                .padding(.leading, 20)
            }
        }
    }

    // MARK: - UID 列表管理

    private var uidListSection: some View {
        @Bindable var vm = viewModel
        return SettingsSection(title: "批量下载列表", icon: "person.2.fill", iconColor: .indigo) {
            HStack(spacing: 8) {
                TextField("输入 UID 或 UID,昵称", text: $vm.newUIDText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .onSubmit { viewModel.addUID() }

                Button {
                    viewModel.addUID()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .disabled(viewModel.newUIDText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if viewModel.uidListEntries.isEmpty {
                Label("暂无用户，添加后可使用「批量下载」功能", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("拖动可调整下载顺序")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                List {
                    ForEach(viewModel.uidListEntries) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)

                            Text(entry.uid)
                                .font(.system(size: 12, design: .monospaced))

                            if let nick = entry.nickname, !nick.isEmpty {
                                Text(nick)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .listRowSeparator(.hidden)
                    }
                    .onMove { source, dest in
                        viewModel.moveUID(from: source, to: dest)
                    }
                    .onDelete { offsets in
                        viewModel.removeUID(at: offsets)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(height: min(CGFloat(viewModel.uidListEntries.count) * 28 + 8, 220))
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - 定时任务

    private var scheduleSection: some View {
        @Bindable var vm = viewModel
        return SettingsSection(title: "定时任务", icon: "clock.fill", iconColor: .purple) {
            Toggle("启用 Crontab 定时任务", isOn: $vm.settings.enableCrontab)
                .font(.system(size: 13))

            if viewModel.settings.enableCrontab {
                HStack {
                    Label("Cron 表达式", systemImage: "calendar.badge.clock")
                        .font(.system(size: 13))

                    TextField("分 时 日 月 周", text: Binding(
                        get: { viewModel.settings.crontab ?? "" },
                        set: { viewModel.settings.crontab = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 160)

                    cronValidationIcon
                }

                Label(
                    "例如 \"14 2 * * *\" 表示每天凌晨 2:14 执行",
                    systemImage: "lightbulb"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Label("批量用户间隔", systemImage: "hourglass")
                    .font(.system(size: 13))
                Spacer()
                TextField("", value: $vm.settings.batchIntervalSeconds, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .multilineTextAlignment(.center)
                Text("秒")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var cronValidationIcon: some View {
        if let cron = viewModel.settings.crontab, !cron.isEmpty {
            if CronExpression(cron) != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("表达式格式正确")
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .help("格式错误，需要 5 个字段：分 时 日 月 周")
            }
        }
    }

    // MARK: - 通知

    private var notificationSection: some View {
        @Bindable var vm = viewModel
        return SettingsSection(title: "完成通知", icon: "bell.fill", iconColor: .red) {
            Toggle("下载完成发送系统通知", isOn: $vm.settings.enableSystemNotification)
                .font(.system(size: 13))

            Divider()

            Text("PushPlus 微信推送")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("PushPlus Token (留空则不推送)", text: Binding(
                get: { viewModel.settings.pushPlusToken ?? "" },
                set: { viewModel.settings.pushPlusToken = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(.caption, design: .monospaced))

            Button {
                NSWorkspace.shared.open(URL(string: "https://www.pushplus.plus/uc.html")!)
            } label: {
                Label("获取 Token", systemImage: "arrow.up.right.square")
                    .font(.caption)
            }
            .buttonStyle(.link)
        }
    }
}

// MARK: - 通用设置分组组件

private struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(iconColor)
                    .frame(width: 22, height: 22)
                    .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.quaternary, lineWidth: 0.5)
            )
        }
    }
}
