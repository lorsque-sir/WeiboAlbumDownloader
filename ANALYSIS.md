# WeiboAlbumDownloader 技术分析报告

> 仓库地址：https://github.com/lorsque-sir/WeiboAlbumDownloader
> Fork 自：https://github.com/hupo376787/WeiboAlbumDownloader
> 分析日期：2026-06-16

---

## 一、项目概述

WeiboAlbumDownloader 是一款基于 **.NET 6.0 + WPF** 的 Windows 桌面应用，用于批量采集指定微博账号下的所有**图片、视频和 LivePhoto**。

核心差异化功能：下载完成后**自动将文件的创建日期、修改日期、访问日期修改为发博时间**，方便用户按日期分组和排序。

---

## 二、技术栈

| 类别 | 技术/版本 |
|------|-----------|
| 运行时 | .NET 6.0 (`net6.0-windows`) |
| UI 框架 | WPF (Windows Presentation Foundation) |
| UI 增强 | MicaWPF 6.3.2（Windows 11 Mica/Acrylic 毛玻璃效果） |
| JSON 解析 | Newtonsoft.Json 13.0.4 |
| HTML 解析 | HtmlAgilityPack 1.12.4 |
| Cookie 获取 | Microsoft.Web.WebView2 1.0.3967.48 |
| 定时任务 | TimeCrontab 3.7.0 + CronExpressionDescriptor 2.44.0 |
| 异常监控 | Sentry 6.0.0 |
| HTTP 通信 | 内置 System.Net.Http.HttpClient |
| CI/CD | GitHub Actions (.NET 6 构建) |

### 依赖关系图

```
WeiboAlbumDownloader.csproj
├── MicaWPF (UI 风格)
├── Newtonsoft.Json (JSON 反序列化)
├── HtmlAgilityPack (HTML DOM 解析)
├── Microsoft.Web.WebView2 (内嵌浏览器)
├── Sentry (崩溃上报)
├── TimeCrontab (Cron 表达式解析)
└── CronExpressionDescriptor (Cron 可读描述)
```

> **注意**：README 中提到的 Selenium 已在代码中被移除，当前 Cookie 获取完全通过 WebView2 实现。

---

## 三、项目结构

```
WeiboAlbumDownloader/                    # 仓库根目录
├── .github/
│   ├── ISSUE_TEMPLATE/bug反馈.md        # Issue 模板
│   └── workflows/dotnet-desktop.yml     # CI 构建脚本
├── img/                                 # README 截图
├── LICENSE                              # MIT 许可证
├── README.md
├── WeiboAlbumDownloader.sln             # VS 解决方案文件
└── WeiboAlbumDownloader/                # 主项目目录
    ├── App.xaml / App.xaml.cs            # 应用入口，Sentry 初始化
    ├── MainWindow.xaml / .xaml.cs        # 主窗口 + 核心下载逻辑 (~1420 行)
    ├── SettingsWindow.xaml / .xaml.cs    # 设置窗口
    ├── WebViewCookieWindow.xaml / .cs    # WebView2 扫码登录窗口
    ├── GlobalVar.cs                     # 全局变量（调试/崩溃上下文）
    ├── AssemblyInfo.cs                  # 程序集信息
    ├── weibo.ico                        # 应用图标
    ├── Assets/                          # UI 图标资源 (PNG)
    ├── Converters/
    │   └── ColorConverter.cs            # WPF 颜色值转换器
    ├── Enums/
    │   ├── WeiboDataSource.cs           # 数据源枚举（4 种）
    │   ├── PicEnum.cs                   # 媒体类型枚举
    │   └── MessageEnum.cs              # 日志级别枚举
    ├── Helpers/
    │   ├── HttpHelper.cs                # HTTP 请求 + 文件下载
    │   ├── WeiboMidHelper.cs            # 超 9 图的 Mid 解析
    │   ├── PushPlusHelper.cs            # 微信推送通知
    │   └── GithubHelper.cs             # 版本更新检测
    └── Models/
        ├── SettingsModel.cs             # 配置项模型
        ├── WeiboCnMobileModel.cs        # m.weibo.cn API 响应模型
        ├── UserAlbumModel.cs            # photo.weibo.com 相册列表模型
        ├── UserAlbumModel2.cs           # weibo.com Ajax 相册列表模型
        ├── AlbumDetailModel.cs          # photo.weibo.com 相册详情模型
        ├── AlbumDetailModel2.cs         # weibo.com Ajax 相册详情模型
        ├── VideoDetailModel.cs          # 视频详情模型
        └── MessageModel.cs             # 日志消息模型
```

### 运行时生成的文件（不在仓库中）

| 文件 | 说明 |
|------|------|
| `Settings.json` | 用户配置（数据源、Cookie、定时任务等） |
| `uidList.txt` | 批量下载的 UID 列表 |
| `Download/` 目录 | 所有下载的媒体文件 |

---

## 四、核心架构与设计模式

### 4.1 整体架构

项目采用**单体 WPF 应用**架构，业务逻辑高度集中在 `MainWindow.xaml.cs` 的 `Start()` 方法中。按 `WeiboDataSource` 枚举值进行分支，实现四种不同的数据采集策略。

```
┌─────────────────────────────────────────────┐
│                  UI 层 (WPF/XAML)            │
│  MainWindow / SettingsWindow / CookieWindow │
├─────────────────────────────────────────────┤
│              业务逻辑层 (Code-Behind)         │
│  Start() 方法 - 4 种数据源分支下载逻辑         │
├─────────────────────────────────────────────┤
│                工具层 (Helpers)               │
│  HttpHelper / WeiboMidHelper / PushPlus     │
├─────────────────────────────────────────────┤
│              数据模型层 (Models)              │
│  API 响应模型 / 配置模型 / UI 模型            │
└─────────────────────────────────────────────┘
```

### 4.2 设计特点

- **Code-Behind 模式**：未使用 MVVM，UI 事件直接在 `.xaml.cs` 中处理
- **异步编程**：大量使用 `async/await` + `Task.Run` 避免阻塞 UI 线程
- **Dispatcher 模式**：通过 `Dispatcher.InvokeAsync` 在后台线程中安全更新 UI
- **CancellationToken**：支持用户手动取消下载任务

---

## 五、四种数据源与采集原理

### 5.1 数据源概览

程序支持 4 种微博 API 数据源，通过 `WeiboDataSource` 枚举控制：

| 枚举值 | 对应域名 | 数据格式 | 采集内容 | 推荐度 |
|--------|----------|---------|---------|--------|
| `WeiboCnMobile` (默认) | m.weibo.cn | JSON | 时间线：图片 + 视频 + LivePhoto | **推荐** |
| `WeiboCn` | weibo.cn | HTML | 时间线：图片 + 视频 | 一般 |
| `WeiboCom1` | photo.weibo.com | JSON | 相册图片（无视频） | 一般 |
| `WeiboCom2` | weibo.com/ajax | JSON | 相册图片（无博文、无日期修改） | 不推荐 |

### 5.2 WeiboCnMobile — m.weibo.cn 移动端 API（推荐）

**API 端点**：
```
https://m.weibo.cn/api/container/getIndex?type=uid&value={uid}&containerid=107603{uid}&since_id={sinceId}&page={page}
```

**工作原理**：
1. 构造 `containerid`：前缀 `107603` + 用户 UID（`107603` 表示时间线，`100505` 表示个人资料）
2. 首次请求 `since_id` 为空，后续从响应的 `CardlistInfo.SinceId` 获取下一页游标
3. 遍历 `Cards` 数组，筛选 `CardType == 9`（微博卡片）且非转发微博
4. 从 `Mblog.PicIds` 提取图片 ID，拼接 CDN URL
5. 从 `Mblog.PageInfo.Urls` 按优先级选取最高清视频
6. 从 `Mblog.LivePhoto` 数组获取 LivePhoto URL

**图片 URL 构造**：
```
https://wx4.sinaimg.cn/large/{pic_id}.jpg
```

**视频清晰度选择优先级**：
```
8K > 4K > 2K > 1080P > 720P > HD > LD
```

**超过 9 张图的处理**：
当 `PicIds.Count != PicNum` 时，调用 `WeiboMidHelper.GetImageIdsByMidAsync(mid)` 通过 PC 端 API 补全完整的图片 ID 列表。

### 5.3 WeiboCn — weibo.cn HTML 解析

**API 端点**：
```
https://weibo.cn/{uid}/profile?page={page}&filter=1
```

**工作原理**：
1. 请求 HTML 页面，使用 `HtmlAgilityPack` 解析 DOM
2. 提取 `div.c` 节点（每条微博）
3. 解析微博内容 (`span.ctt`)、发布时间 (`span.ct`)、来源设备
4. 判断媒体类型：
   - "组图共 N 张" → 获取组图链接页面，解析所有缩略图并转大图
   - "原图" → 提取单张原图链接
   - `s/video/show` → 转换为 `s/video/object` 获取视频流地址
5. 翻页通过 `input[type=hidden]` 获取总页数

**时间解析**：支持 "N分钟前" 和 "今天 HH:mm" 两种格式的相对时间推算。

### 5.4 WeiboCom1 — photo.weibo.com 相册 API

**API 端点**：
```
# 获取相册列表
https://photo.weibo.com/albums/get_all?uid={uid}&page=1

# 获取相册内图片
https://photo.weibo.com/photos/get_all?uid={uid}&album_id={id}&count=90&page={page}&type={type}
```

**工作原理**：
1. 获取用户所有相册（头像相册、微博配图、自拍等）
2. 遍历每个相册，分页获取图片列表
3. 通过 `pic_host + "/large/" + pic_name` 构造原图 URL
4. 时间戳转换：`DateTime.UnixEpoch.AddSeconds(photo.timestamp + 8 * 3600)` (UTC+8)

### 5.5 WeiboCom2 — weibo.com Ajax API

**API 端点**：
```
# 获取相册墙
https://weibo.com/ajax/profile/getImageWall?uid={uid}&sinceid=0&has_album=true

# 获取相册详情
https://weibo.com/ajax/profile/getAlbumDetail?containerid={containerid}&since_id={sinceId}
```

**局限性**：无法获取博文内容，无法修改文件日期，数据获取可能不全。

---

## 六、核心下载流程

```
用户输入 UID
    │
    ▼
读取 Settings.json 配置
    │
    ▼
根据 DataSource 选择 API ──────────────────┐
    │                                       │
    ▼                                       │
分页请求数据（JSON 解析 / HTML 解析）         │
    │                                       │
    ▼                                       │
提取媒体 URL 列表                            │
（图片/视频/LivePhoto）                       │
    │                                       │
    ▼                                       │
构造本地文件名                               │
（日期_博文内容_编号.扩展名）                  │
    │                                       │
    ▼                                       │
┌─ File.Exists? ──┐                         │
│  是：跳过+计数  │  否：下载文件             │
│       │         │       │                  │
│       ▼         │       ▼                  │
│  跳过数>阈值？  │  SetFileTime()           │
│   是→跳到下一用户│  修改文件日期为发博时间   │
│   否→继续       │       │                  │
└─────────────────┘       │                  │
    │                     │                  │
    ▼                     ▼                  │
随机延时 5-10 秒 ─────────────── 翻下一页 ───┘
    │
    ▼
下载完成 → PushPlus 通知 → 写入 uidList.txt
```

---

## 七、关键机制详解

### 7.1 Cookie 获取（WebView2）

**文件**：`WebViewCookieWindow.xaml.cs`

程序通过 WebView2 内嵌浏览器打开微博 SSO 登录页，用户扫码后自动提取 Cookie。

| 数据源 | 登录 URL |
|--------|----------|
| WeiboCn | `https://passport.weibo.com/sso/signin?entry=wapsso&source=wapssowb&url=https://weibo.cn` |
| WeiboCnMobile | `https://passport.weibo.com/sso/signin?entry=wapsso&source=wapsso&url=https://m.weibo.cn` |
| WeiboCom | `https://passport.weibo.com/sso/signin?entry=miniblog&source=miniblog&url=https://weibo.com/` |

Cookie 提取逻辑：从多个域（`weibo.cn`、`m.weibo.cn`、`passport.weibo.com`）合并 Cookie，去重后以 `name=value; ...` 格式拼接。

**Cookie 域分离**：`weibo.cn` 和 `weibo.com` 的 Cookie 不通用，配置中需分别维护 `WeiboCnCookie` 和 `WeiboComCookie`。

### 7.2 HTTP 请求封装

**文件**：`Helpers/HttpHelper.cs`

统一入口方法 `GetAsync<T>(url, dataSource, cookie, fileName, logAction)`：

- **数据请求模式**（`fileName` 为空）：附加 Cookie、User-Agent、Referer 等请求头，返回 JSON 反序列化对象或 HTML 字符串
- **文件下载模式**（`fileName` 非空）：不附加 Cookie（CDN 直链），将响应流写入本地文件
- **文件名安全处理**：清理非法字符、截断超长文件名（>200字符）、重名自动追加编号 `(1)(2)...`
- **GZip 解压**：自动处理 GZip/Deflate 压缩的响应
- **Cookie 失效检测**：响应内容包含"登录 - 微博"时提示 Cookie 失效

### 7.3 文件日期修改

**文件**：`MainWindow.xaml.cs` - `SetFileTime()` 方法

```csharp
private void SetFileTime(string filename, DateTime timestamp)
{
    File.SetCreationTime(filename, timestamp);
    File.SetLastWriteTime(filename, timestamp);
    File.SetLastAccessTime(filename, timestamp);
}
```

这是本项目的核心差异化功能。不同数据源的时间来源：
- **m.weibo.cn**：`Mblog.CreatedAt`（格式：`ddd MMM dd HH:mm:ss K yyyy`）
- **weibo.cn**：从"N分钟前"或"今天 HH:mm"推算
- **photo.weibo.com**：`DateTime.UnixEpoch.AddSeconds(photo.timestamp + 8*3600)`
- **weibo.com Ajax**：不支持日期修改

### 7.4 反爬策略

每次翻页后随机等待 **5~10 秒**：
```csharp
Random rd = new Random();
int rnd = rd.Next(5000, 10000);
await Task.Delay(rnd);
```

批量下载/定时任务中，不同用户之间额外等待 **60 秒**。

### 7.5 智能跳过（增量下载）

通过 `CountDownloadedSkipToNextUser` 配置项（默认 20）实现：
- 每次跳过已存在的文件时，`countDownloadedSkipToNextUser++`
- 累计跳过数超过阈值后，判定该用户已下载过，自动跳到下一个用户
- 同时支持 `File.Exists()` 级别的文件去重

### 7.6 定时任务

**实现方式**：使用 `TimeCrontab` 库解析 Cron 表达式，在后台长期运行的 `Task` 中循环：

```csharp
var cron = Crontab.Parse(settings?.Crontab);  // 如 "14 2 * * *"
while (true)
{
    await Task.Delay((int)cron.GetSleepMilliseconds(DateTime.Now));
    // 遍历 uidList.txt 中的所有 UID 执行下载
}
```

UI 上通过 `CronExpressionDescriptor` 将 Cron 表达式转为人类可读的中文描述。

### 7.7 消息推送

**文件**：`Helpers/PushPlusHelper.cs`

通过 PushPlus API 将下载完成消息推送到微信：
```
http://www.pushplus.plus/send?token={token}&title=微博相册下载&content={info}
```

### 7.8 版本更新检测

**文件**：`Helpers/GithubHelper.cs`

启动时从 GitHub/Gitee 的 tags 页面提取最新版本号，与本地 `currentVersion` 对比，如有新版本弹窗提示。

---

## 八、微博 API 端点汇总

### 8.1 数据采集 API

| 用途 | URL 模板 | 数据源 |
|------|----------|--------|
| 移动端时间线 | `https://m.weibo.cn/api/container/getIndex?type=uid&value={uid}&containerid=107603{uid}&since_id={sinceId}&page={page}` | WeiboCnMobile |
| weibo.cn 时间线 | `https://weibo.cn/{uid}/profile?page={page}&filter=1` | WeiboCn |
| 相册列表 | `https://photo.weibo.com/albums/get_all?uid={uid}&page=1` | WeiboCom1 |
| 相册图片 | `https://photo.weibo.com/photos/get_all?uid={uid}&album_id={id}&count=90&page={page}&type={type}` | WeiboCom1 |
| Ajax 相册墙 | `https://weibo.com/ajax/profile/getImageWall?uid={uid}&sinceid=0&has_album=true` | WeiboCom2 |
| Ajax 相册详情 | `https://weibo.com/ajax/profile/getAlbumDetail?containerid={containerid}&since_id={sinceId}` | WeiboCom2 |
| PC 微博详情 | `https://weibo.com/ajax/statuses/show?id={mid}&locale=zh-CN&isGetLongText=true` | WeiboMidHelper |
| 移动微博详情 | `https://m.weibo.cn/statuses/show?id={mid}` | WeiboMidHelper |

### 8.2 媒体 CDN

| 类型 | URL 模板 |
|------|----------|
| 大图 | `https://wx4.sinaimg.cn/large/{pic_id}.jpg` |
| 头像 | `https://tvax2.sinaimg.cn/large/{filename}` |
| WeiboCom1 原图 | `{pic_host}/large/{pic_name}` |
| 视频 | 来自 API 响应中的 stream URL（多清晰度 mp4） |
| LivePhoto | 来自 `Mblog.LivePhoto[]` 直接 URL (.mov) |

### 8.3 第三方服务

| 用途 | URL |
|------|-----|
| SSO 登录 | `https://passport.weibo.com/sso/signin?...` |
| PushPlus 推送 | `http://www.pushplus.plus/send?token={token}&title={title}&content={content}` |
| 版本检查 (GitHub) | `https://github.com/hupo376787/WeiboAlbumDownloader/tags` |
| 版本检查 (Gitee) | `https://gitee.com/hupo376787/weibo-album-downloader/tags` |

---

## 九、数据模型设计

### 9.1 配置模型 (`SettingsModel`)

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `DataSource` | WeiboDataSource | WeiboCnMobile | 数据源选择 |
| `ShowHeadImage` | bool | true | 首页是否显示头像 |
| `WeiboCnCookie` | string? | null | weibo.cn / m.weibo.cn Cookie |
| `WeiboComCookie` | string? | null | weibo.com Cookie |
| `PushPlusToken` | string? | null | PushPlus 推送 Token |
| `EnableCrontab` | bool | true | 是否开启定时任务 |
| `Crontab` | string? | "14 2 * * *" | Cron 表达式 |
| `CountDownloadedSkipToNextUser` | int | 20 | 跳过阈值 |
| `EnableDatetimeRange` | bool | false | 是否限定时间范围 |
| `StartDateTime` | DateTime? | null | 起始时间 |
| `EnableDownloadVideo` | bool | true | 是否下载视频 |
| `EnableDownloadLivePhoto` | bool | true | 是否下载 LivePhoto |
| `EnableShortenName` | bool | false | 是否缩短文件名 |

### 9.2 m.weibo.cn 核心数据结构

```
WeiboCnMobileModel
└── Data
    ├── CardlistInfo
    │   ├── SinceId (分页游标)
    │   └── Total (总条数)
    └── Cards[]
        └── Mblog
            ├── CreatedAt (发博时间)
            ├── Text (博文内容)
            ├── PicIds[] (图片 ID 列表)
            ├── PicNum (实际图片数，可能 > PicIds.Count)
            ├── PageInfo
            │   └── Urls (视频各清晰度 URL)
            ├── LivePhoto[] (LivePhoto URL 列表)
            ├── User
            │   ├── ScreenName (昵称)
            │   └── AvatarHd (头像)
            └── RetweetedStatus (转发标记，非空则跳过)
```

---

## 十、文件命名规则

### 下载目录结构

```
Download/
└── 昵称(UID)/              # m.weibo.cn 数据源
    ├── 昵称                 # 空文件，用于标识用户
    ├── {头像文件名}.jpg
    ├── 2024-03-15 14_30_00博文内容_1.jpg
    ├── 2024-03-15 14_30_00博文内容_2.jpg
    ├── 2024-03-15 14_30_00博文内容_3.mp4   # 视频
    └── 2024-03-15 14_30_00博文内容_4.mov   # LivePhoto
```

### 命名格式

```
{yyyy-MM-dd HH_mm_ss}{博文内容}_{编号}.{扩展名}
```

开启 `EnableShortenName` 后：
```
{yyyy-MM-dd HH_mm_ss}_{编号}.{扩展名}
```

---

## 十一、代码架构评估

### 11.1 优点

1. **功能完整**：支持图片、视频、LivePhoto 三种媒体类型
2. **多数据源**：4 种 API 互为备选，覆盖面广
3. **用户体验好**：WebView2 扫码登录、Mica 毛玻璃 UI、实时日志
4. **差异化功能**：文件日期修改为发博时间，其他工具少有
5. **增量下载**：智能跳过已下载文件，支持断点续传
6. **自动化**：Crontab 定时任务 + PushPlus 微信通知
7. **反爬处理**：随机延时降低被限流风险

### 11.2 可改进方向

1. **架构耦合**：核心下载逻辑（~1000 行）全部集中在 `MainWindow.xaml.cs` 的 `Start()` 方法中，建议拆分为独立的 Service 层
2. **未使用 MVVM**：直接在 Code-Behind 中操作 UI，不利于测试和维护，建议引入 CommunityToolkit.Mvvm
3. **HttpClient 使用**：每次请求 `new HttpClient(new HttpClientHandler())`，未使用单例或 `IHttpClientFactory`，高频请求时可能导致 Socket 耗尽
4. **代码重复**：四种数据源的下载逻辑存在大量重复代码（文件存在检查、文件名构造、下载、日期修改），可抽取为公共方法
5. **异常处理**：部分 catch 块为空或仅打印日志，可加强错误恢复策略
6. **Sentry DSN 硬编码**：`App.xaml.cs` 中 Sentry DSN 明文写入代码，公开仓库中应使用环境变量或配置文件
7. **跨平台限制**：依赖 WPF 和 Windows 文件系统 API，无法在 macOS/Linux 运行

### 11.3 重构建议

如果要进行重构，建议按以下方向：

```
WeiboAlbumDownloader/
├── Services/
│   ├── IWeiboDataProvider.cs          # 数据源抽象接口
│   ├── WeiboCnMobileProvider.cs       # m.weibo.cn 实现
│   ├── WeiboCnProvider.cs             # weibo.cn 实现
│   ├── WeiboComProvider.cs            # weibo.com 实现
│   ├── DownloadService.cs             # 通用下载逻辑
│   └── FileNamingService.cs           # 文件命名策略
├── ViewModels/
│   ├── MainViewModel.cs               # MVVM ViewModel
│   └── SettingsViewModel.cs
└── Views/
    ├── MainWindow.xaml
    └── SettingsWindow.xaml
```

采用**策略模式**处理不同数据源，提取公共的下载/命名/日期修改逻辑，使代码更易维护和测试。

---

## 十二、总结

WeiboAlbumDownloader 是一个功能完整、实用性强的微博媒体下载工具。它通过 4 种数据源策略覆盖了微博的图片、视频和 LivePhoto 下载需求，核心差异化在于**自动修改文件日期为发博时间**。技术栈基于 .NET 6 + WPF + MicaWPF，Cookie 通过 WebView2 扫码获取，支持 Crontab 定时任务和 PushPlus 微信通知。

主要改进空间在于代码架构层面：将单体的 `MainWindow.xaml.cs` 拆分为 Service 层 + MVVM 模式，以提升可维护性和可测试性。
