import SwiftUI

// MARK: - 设置界面

/// 应用设置界面，以分组形式展示所有可配置项
/// 包含：数据源选择、Cookie 配置、下载选项、定时任务、PushPlus 推送
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置")
                    .font(.title2.bold())
                Spacer()
                Button("完成") {
                    viewModel.save()
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    dataSourceSection
                    cookieSection
                    downloadOptionsSection
                    scheduleSection
                    pushPlusSection
                }
                .padding()
            }
        }
    }

    // MARK: - 数据源选择

    private var dataSourceSection: some View {
        GroupBox("数据源") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("数据源", selection: $viewModel.settings.dataSource) {
                    ForEach(WeiboDataSource.allCases) { source in
                        Text(source.displayName).tag(source)
                    }
                }
                .pickerStyle(.segmented)

                Text(viewModel.settings.dataSource.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Cookie 配置

    /// Cookie 区域：支持扫码获取（弹出 WKWebView）和手动粘贴两种方式
    private var cookieSection: some View {
        GroupBox("Cookie 配置") {
            VStack(alignment: .leading, spacing: 12) {
                // weibo.cn Cookie
                HStack {
                    VStack(alignment: .leading) {
                        Text("weibo.cn / m.weibo.cn Cookie")
                            .font(.subheadline.bold())
                        Text(viewModel.hasCnCookie ? "已配置" : "未配置")
                            .font(.caption)
                            .foregroundStyle(viewModel.hasCnCookie ? .green : .red)
                    }
                    Spacer()
                    Button("扫码获取") {
                        viewModel.showCnCookieSheet = true
                    }
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
                }

                TextField("或手动粘贴 Cookie", text: $viewModel.cnCookieText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))

                Divider()

                // weibo.com Cookie
                HStack {
                    VStack(alignment: .leading) {
                        Text("weibo.com Cookie")
                            .font(.subheadline.bold())
                        Text(viewModel.hasComCookie ? "已配置" : "未配置")
                            .font(.caption)
                            .foregroundStyle(viewModel.hasComCookie ? .green : .red)
                    }
                    Spacer()
                    Button("扫码获取") {
                        viewModel.showComCookieSheet = true
                    }
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

                TextField("或手动粘贴 Cookie", text: $viewModel.comCookieText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 下载选项

    private var downloadOptionsSection: some View {
        GroupBox("下载选项") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("显示头像", isOn: $viewModel.settings.showHeadImage)
                Toggle("下载视频", isOn: $viewModel.settings.enableDownloadVideo)
                Toggle("下载 LivePhoto", isOn: $viewModel.settings.enableDownloadLivePhoto)
                Toggle("短文件名 (仅日期+编号)", isOn: $viewModel.settings.enableShortenName)

                Divider()

                // 智能跳过：连续遇到 N 个已下载文件时认为后续内容已备份，自动跳过
                HStack {
                    Text("智能跳过阈值")
                    Spacer()
                    TextField("", value: $viewModel.settings.countDownloadedSkipToNextUser, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onChange(of: viewModel.settings.countDownloadedSkipToNextUser) { newVal in
                            viewModel.settings.countDownloadedSkipToNextUser = max(1, min(999, newVal))
                        }
                    Text("个已存在文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("同时下载数")
                    Spacer()
                    Picker("", selection: $viewModel.settings.maxConcurrentDownloads) {
                        Text("1").tag(1)
                        Text("3").tag(3)
                        Text("5").tag(5)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }

                Divider()

                Toggle("时间范围过滤", isOn: $viewModel.settings.enableDatetimeRange)
                if viewModel.settings.enableDatetimeRange {
                    DatePicker(
                        "起始日期",
                        selection: Binding(
                            get: { viewModel.settings.startDateTime ?? Date() },
                            set: { viewModel.settings.startDateTime = $0 }
                        ),
                        displayedComponents: .date
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 定时任务

    private var scheduleSection: some View {
        GroupBox("定时任务") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("启用 Crontab 定时任务", isOn: $viewModel.settings.enableCrontab)

                if viewModel.settings.enableCrontab {
                    HStack {
                        Text("Cron 表达式")
                        TextField("", text: Binding(
                            get: { viewModel.settings.crontab ?? "" },
                            set: { viewModel.settings.crontab = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)

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
                    Text("例如 \"14 2 * * *\" 表示每天凌晨 2:14 执行")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - PushPlus 推送

    private var pushPlusSection: some View {
        GroupBox("PushPlus 微信推送") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("PushPlus Token (留空则不推送)", text: Binding(
                    get: { viewModel.settings.pushPlusToken ?? "" },
                    set: { viewModel.settings.pushPlusToken = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)

                Button("获取 Token") {
                    NSWorkspace.shared.open(URL(string: "https://www.pushplus.plus/uc.html")!)
                }
                .font(.caption)
            }
            .padding(.vertical, 4)
        }
    }
}
