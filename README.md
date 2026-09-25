# MDay - macOS 本地 Markdown 日记本

一款原生 macOS 日记应用。**写的每一篇都是标准 Markdown 文件，存在你自己的文件夹里** —— 不上传服务器，不经过第三方，想换电脑把文件夹拷走就完成了全部迁移。

## 功能特性

### 写作

- **单栏即时渲染**：写的是 Markdown 语法，看到的是排好版的样子。光标停在哪一行，那一行的标记就露出来方便直接改
- **三种视图**：即时渲染 / 纯源码 / 纯预览，工具条一键切换
- **自动保存**：没有保存按钮，敲完 0.7 秒自动落盘
- **信纸底纹**：纯白 / 横线 / 方格 / 点阵 / 米黄 / 樱粉
- **排版可调**：紧凑 / 舒展 / 杂志三套预设，行高、段间距、标题缩放、版心宽度都能单独调
- **九宫格日记**：内置三套模板，九个问题可以自己改、自己加
- **写作城市**：每篇记下当时所在的城市，写在文件里，拷到别的电脑也不会丢
- **天气**：新建今天的日记时自动抓取，也可以手动改

### 日记本与整理

- **多日记本**：12 种颜色 + 48 个图标 + 拖动排序
- **改名安全**：名字和磁盘目录分离，改名不会丢日记
- **五种排序**：最新写的 / 最早写的 / 最近修改的 / 字数最多的 / 按标题
- **日历**：月历带农历、节气、节日、调休标记，点某天看当天的黄历与日记
- **统计**：写作热力图、日记本分布、常用标签、平均每篇字数
- **那年今日**、**全文搜索**

### 农历 · 黄历 · 节假日 · 星座

- **农历**：日期、月名、二十四节气、干支纪年 / 月 / 日、生肖
- **黄历**：建除十二神、黄道黑道十二神、宜忌、冲煞（民间传统说法，仅供参考）
- **法定节假日与调休**：收录 2024 / 2025 / 2026 三年，日历上直接标「休」「班」
- **星座运势**：按日期显示星座与综合、感情、事业、财运（娱乐向）

### 每日一句

侧边栏顶部每天展示一条凯文·凯利《宝贵的人生建议》，内置 499 条，按天取模 —— 同一天打开几次都是同一句。

### 小迹 AI 助手

- 流式对话，可以把当前这篇 / 今天 / 最近 7 天 / 本月 / 全部日记作为上下文
- 一键总结、整篇润色、挑错别字
- 默认 DeepSeek，任何 OpenAI 格式的接口都能接（通义、智谱、Kimi、本地 Ollama）
- 面板宽度可拖动，双击恢复默认

### 隐私与安全

- **打开密码**：只锁界面，磁盘上仍是明文 Markdown，方便随时用别的工具打开
- **文件加密**：可开 AES-256-GCM，开启后正文以密文写盘，离开这个 App 无法直接阅读
- **触控 ID / 面容 ID 解锁**：锁屏时自动弹指纹，按一下就能进
- **日记本单独上锁**：某一本可以单独上锁，点开时要过指纹或密码；没解锁之前，它的日记不出现在任何列表、搜索、统计、日历、AI 上下文和导出里
- **本机保险库**：AI API Key 和指纹解锁用的密码加密落盘，密钥由主板 UUID + 当前用户 uid 派生，换台机器解不开

### 界面

- 浅色 / 深色 / 跟随系统
- 界面字号四档（紧凑 / 标准 / 大 / 特大），默认「大」
- 强调色是暖赤陶 `#C85A37`，不用系统蓝
- 设置页 8 页：通用、写作区、安全与锁、小迹 AI、天气、农历与黄历、数据与备份、关于

## 系统要求

- macOS 14.0 (Sonoma) 或更高
- Xcode Command Line Tools（仅编译时需要，`xcode-select --install`）
- 不需要完整 Xcode，不需要 Xcode 工程文件

## 安装与运行

```bash
git clone https://github.com/mikizhu520/m-day-diary.git
cd m-day-diary
chmod +x build.sh
./build.sh
```

构建完成后应用在 `dist/MDay.app`，双击即可运行。装到应用程序目录：

```bash
cp -R dist/MDay.app /Applications/
```

首次启动会走一遍引导：选数据保存位置 → 可选设置打开密码与文件加密。

## 使用说明

1. 左侧是导航：今天 / 全部日记 / 那年今日 / 日历 / 统计，下面是日记本和标签
2. 中间是日记列表，按天分组；顶部可排序
3. 右边是写作区，直接写 Markdown，不需要按任何保存键
4. 侧边栏日记本可以拖动排序，右键能改名、换颜色图标、单独上锁、设为默认
5. AI 助手先去 `⌘,` → 「小迹 AI」里填一个 API Key；天气城市在 `⌘,` → 「天气」里改

常用快捷键：`⌘N` 新建 · `⌘⇧N` 九宫格 · `⌘T` 今天 · `⌘F` 搜索 · `⌘J` AI 助手 · `⌘L` 锁定 · `⌘,` 设置

## 数据存在哪里

默认目录 `~/Documents/日迹日记/`（可在设置里更改）：

```
日迹日记/
├── journals/<日记本ID>/<年-月-日>/<时间>-<随机>.md   每篇日记一个文件
└── attachments/                                     插入的图片
```

每篇都是标准 Markdown，开头一小段元信息（标题、标签、心情、天气、城市、时间），用 Typora、VS Code、Obsidian 都能直接打开。

设置与密码校验值存在 `~/Library/Application Support/日迹/config.json`。

> 内部标识（Bundle ID `com.meiling.riji`、数据目录 `日迹日记/`）刻意保留了旧名，**不要去改** —— 改了等于换了一个 App，配置和保险库都会读不到。

## 项目结构

```
m-day-diary/
├── app/Sources/RiJi/
│   ├── App.swift                    入口、主窗口、菜单
│   ├── Models.swift                 数据模型
│   ├── Store.swift                  仓库：读写 .md、锁、日记本
│   ├── Crypto.swift                 PBKDF2 / AES-GCM
│   ├── Vault.swift                  本机保险库
│   ├── Biometric.swift              触控 ID / 面容 ID
│   ├── LockView.swift               锁屏与首次引导
│   ├── JournalUnlockView.swift      日记本单独解锁面板
│   ├── SidebarView.swift            侧边栏
│   ├── EntryListView.swift          中栏列表
│   ├── JournalEditor.swift          日记本新建 / 编辑
│   ├── EditorView.swift             写作区
│   ├── RichEditor.swift             NSTextView 封装
│   ├── LiveMarkdown.swift           即时渲染引擎
│   ├── MDType.swift                 排版规格
│   ├── MarkdownView.swift           预览渲染
│   ├── Paper.swift                  信纸底纹
│   ├── GridJournal.swift            九宫格日记
│   ├── CalendarView.swift / Heatmap.swift   日历与统计
│   ├── Almanac.swift / Holiday.swift / Zodiac.swift   农历、黄历、节假日、星座
│   ├── DailyAdvice.swift / LifeAdvice.swift           每日一句
│   ├── Weather.swift                Open-Meteo 天气
│   ├── AIPanel.swift / AIService.swift                AI 助手
│   ├── SettingsView.swift           设置（8 页）
│   ├── Export.swift                 导出与备份
│   ├── Theme.swift                  视觉规范与字号缩放
│   └── SelfTest.swift               565 项自检
├── tools/
│   ├── gen_icon.swift               用代码画应用图标
│   └── privacy-check.sh             提交前的隐私体检
├── build.sh                         编译 + 组装 .app + 生成图标 + 签名
└── README.md
```

## 技术栈

- **Swift / SwiftUI**：全部界面
- **AppKit**：`NSTextView` 富文本编辑、窗口、菜单、毛玻璃
- **Foundation**：`Calendar(identifier: .chinese)` 农历、`URLSession` 网络
- **CryptoKit**：PBKDF2 密钥派生、AES-256-GCM
- **LocalAuthentication**：触控 ID / 面容 ID
- **CoreGraphics**：应用图标绘制
- **IOKit**：读取主板 UUID 作为保险库密钥的一部分

**零第三方依赖。** 没有 `Package.resolved`，没有 CocoaPods，没有 SPM 远程包。

## 隐私说明

- 所有日记都是本地 `.md` 文件，不上传任何服务器
- 天气请求只发送城市名，不发送日记内容
- AI 对话只在你主动使用时才发出，内容是你选定的上下文范围；API Key 存在本机保险库
- 不收集任何统计信息，不联网心跳，不检查更新
- 打开密码、日记本锁、文件加密全部在本机完成，没有找回后门

## 开发者

**Miki Zhu**

- GitHub：[@mikizhu520](https://github.com/mikizhu520/)
- 邮箱：750856902@qq.com
- 微信公众号：**逍遥小斑鸠**

## License

MIT
