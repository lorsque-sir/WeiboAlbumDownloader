import SwiftUI

// MARK: - 设置界面

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    dataSourceSection
                    cookieSection
                    downloadOptionsSection
                    scheduleSection
                    pushPlusSection
                }
                .padding(20)
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
        SettingsSection(title: "数据源", icon: "antenna.radiowaves.left.and.right", iconColor: .blue) {
            Picker("数据源", selection: $viewModel.settings.dataSource) {
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
        SettingsSection(title: "Cookie 配置", icon: "key.fill", iconColor: .orange) {
            cookieRow(
                domain: "weibo.cn / m.weibo.cn",
                isConfigured: viewModel.hasCnCookie,
                cookieText: $viewModel.cnCookieText,
                onScan: { viewModel.showCnCookieSheet = true }
            )
            .sheet(isPresented: $viewModel.showCnCookieSheet) {
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
                cookieText: $viewModel.comCookieText,
                onScan: { viewModel.showComCookieSheet = true }
            )
            .sheet(isPresented: $viewModel.showComCookieSheet) {
                CookieWebView(
                    dataSource: .weiboCom1,
                    onCookieObtained: { cookie in
                        viewModel.setComCookie(cookie)
                        viewModel.showComCookieSheet = false
                    }
                )
                .frame(minWidth: 450, minHeight: 550)
            }
        }
    }

    private func cookieRow(
        domain: String,
        isConfigured: Bool,
        cookieText: Binding<String>,
        onScan: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(domain)
                        .font(.subheadline.bold())

                    HStack(spacing: 4) {
                        Circle()
                            .fill(isConfigured ? .green : .red)
                            .frame(width: 6, height: 6)
                        Text(isConfigured ? "已配置" : "未配置")
                            .font(.caption)
                            .foregroundStyle(isConfigured ? .green : .red)
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

    // MARK: - 下载选项

    private var downloadOptionsSection: some View {
        SettingsSection(title: "下载选项", icon: "arrow.down.doc.fill", iconColor: .green) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("显示头像", isOn: $viewModel.settings.showHeadImage)
                Toggle("下载视频", isOn: $viewModel.settings.enableDownloadVideo)
                Toggle("下载 LivePhoto", isOn: $viewModel.settings.enableDownloadLivePhoto)
                Toggle("短文件名 (仅日期+编号)", isOn: $viewModel.settings.enableShortenName)
            }
            .font(.system(size: 13))

            Divider()

            HStack {
                Label("智能跳过阈值", systemImage: "forward.fill")
                    .font(.system(size: 13))
                Spacer()
                TextField("", value: $viewModel.settings.countDownloadedSkipToNextUser, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .multilineTextAlignment(.center)
                    .onChange(of: viewModel.settings.countDownloadedSkipToNextUser) { newVal in
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
                Picker("", selection: $viewModel.settings.maxConcurrentDownloads) {
                    Text("1").tag(1)
                    Text("3").tag(3)
                    Text("5").tag(5)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            Divider()

            Toggle("时间范围过滤", isOn: $viewModel.settings.enableDatetimeRange)
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

    // MARK: - 定时任务

    private var scheduleSection: some View {
        SettingsSection(title: "定时任务", icon: "clock.fill", iconColor: .purple) {
            Toggle("启用 Crontab 定时任务", isOn: $viewModel.settings.enableCrontab)
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

    // MARK: - PushPlus

    private var pushPlusSection: some View {
        SettingsSection(title: "PushPlus 微信推送", icon: "bell.fill", iconColor: .red) {
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
