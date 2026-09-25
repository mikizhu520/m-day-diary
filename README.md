# MDay · 本地优先的 Markdown 日记本

一款原生 macOS 日记应用。**写的每一篇都是标准 Markdown 文件，存在你自己的文件夹里** —— 不上传任何服务器，不经过任何第三方，不用的时候把文件夹拷走就完成了全部迁移。

> 名字来自 "Markdown" + "Day"。内部标识（Bundle ID `com.meiling.riji`、数据目录 `日迹日记/`）刻意保持旧名不变 —— 改显示名不会丢数据，改路径会。

- 已安装位置：`/Applications/MDay.app`
- 工程源码：`app/`（Swift Package，纯 SwiftUI + AppKit，无第三方依赖）
- 重新编译：在本目录执行 `./build.sh`，产物在 `dist/MDay.app`

---

## 功能特性

### 写作

- **单栏即时渲染**：写的是 Markdown 语法，看到的是排好版的样子。敲 `# 标题` 当场变大变粗，`#` 自己消失；`**加粗**`、`*斜体*`、`` `代码` ``、`[链接](url)`、引用、列表、待办、表格、代码块、分割线全部当场生效
- **光标所在行露出语法**：光标回到哪一行，那一行的标记就重新显出来方便直接改，移开又收回去
- **三种视图**：即时渲染 / 纯源码 / 纯预览，工具条右侧一键切换
- **自动保存**：不设保存按钮。敲完 0.7 秒自动落盘，切走、关窗、退出都会 flush
- **信纸底纹**：纯白 / 横线 / 方格 / 点阵 / 米黄 / 樱粉，六种写作区背景
- **排版可调**：紧凑 / 舒展 / 杂志三套预设，行高、段间距、标题缩放、版心宽度、装饰开关全部可单独微调
- **九宫格日记**：内置三套模板（九个问题），在新建时直接引用着回答，问题本身也可以自己改、自己加
- **写作城市**：每篇日记记下当时所在的城市，写在 front matter 里，拷到别的电脑也不会丢

### 日记本与整理

- **多日记本**：颜色（12 色）+ 图标（48 个 SF Symbols，分六组）+ 拖动排序
- **改名安全**：`Journal.name` 和 `id` 分离，磁盘目录是 `journals/<id>/…`，改名只动 name，一篇日记都不会丢
- **五种排序**：最新写的 / 最早写的 / 最近修改的 / 字数最多的 / 按标题
- **日历视图**：月历每格显示农历、节气、节日、调休标记；点某天看当天的黄历与日记
- **统计**：热力图（26 周 / 52 周）、日记本分布、常用标签、写作习惯、平均每篇字数
- **那年今日**：自动捞出往年同一天的日记
- **全文搜索**：标题、正文、标签一起搜

### 农历 · 黄历 · 节假日 · 星座

- **农历**：日期、月名、节气（二十四节气按太阳黄经算出）、干支纪年 / 纪月 / 纪日、生肖
- **黄历**：建除十二神、黄道黑道十二神、宜忌、冲煞
- **法定节假日与调休**：收录 2024 / 2025 / 2026 三年国务院安排，日历上直接标「休」「班」
- **星座运势**：按生日或当天日期显示太阳星座，附综合、感情、事业、财运与幸运色 / 数字

### 每日一句

侧边栏顶部每天展示一条凯文·凯利《宝贵的人生建议》。内置 499 条（逐条从中文版 epub 抽出，原文原样保留），按天取模，**同一天无论重开几次都是同一句**。想换可以点「换一句」，不落盘，明天自动回到按天那一条。

### 小迹 AI 助手

- 流式对话，可把当前这篇 / 今天 / 最近 7 天 / 本月 / 全部日记作为上下文
- 一键总结、整篇润色、挑错别字
- 接口默认 DeepSeek，**任何 OpenAI 格式的接口都能接**（通义、智谱、Kimi、本地 Ollama）
- 面板宽度可拖动，双击恢复默认；宽度记在 UserDefaults 里

### 隐私与安全

- **打开密码**：只锁界面，磁盘上仍是明文 Markdown（方便随时用别的工具打开）
- **文件加密**：可开 AES-256-GCM，开启后正文以密文写盘，离开这个 App 无法直接阅读
- **触控 ID / 面容 ID 解锁**：锁屏时自动弹指纹，按一下就能进
- **日记本单独上锁**：某一本可以单独上锁，点开时要过指纹或密码；未解锁时它的日记不出现在任何列表、搜索、统计、日历、AI 上下文和导出里
- **本机保险库**：AI API Key 和指纹解锁用的密码 AES-GCM 加密落盘，密钥由主板 UUID + 当前用户 uid 派生，换台机器解不开

### 界面

- 浅色 / 深色 / 跟随系统
- 界面字号四档（紧凑 / 标准 / 大 / 特大），默认「大」
- 强调色是暖赤陶 `#E8623C`，不用系统蓝
- 设置页共 8 页：通用、写作区、安全与锁、小迹 AI、天气、农历与黄历、数据与备份、关于

---

## 系统要求

- macOS 14.0 (Sonoma) 或更高
- Xcode Command Line Tools（仅编译时需要，`xcode-select --install`）
- 不需要完整 Xcode，不需要 Xcode 工程文件

---

## 安装与运行

```bash
git clone https://github.com/mikizhu520/m-day-diary.git
cd m-day-diary
chmod +x build.sh
./build.sh
```

构建脚本会依次做四件事：编译 release 版 Swift、组装 `.app` 目录、用 CoreGraphics 画应用图标并压成 `.icns`、ad-hoc 签名。

图标是代码画的，不是图片文件（`tools/gen_icon.swift`，约 100 行）。样式：**白色圆角底板 + 一个暖赤陶色的本子 + 本子上的三行白字**，第一行满不透明，后两行退到 55% 做层次。

两个刻意的决定：

- **白底板必须有一道边界**。图标落在浅色壁纸或 Finder 白底上时，纯白会和背景糊在一起，所以补了一条发丝级的暖灰描边加一层很淡的投影（alpha 0.10），都压到「近看才有」的程度。
- **本子要占够地方**。白底板比原来的暖色底板空得多，本子画小了缩到 32×32 就只剩一块白板上糊个小色块，所以尺寸从 0.46 提到 0.515。

改完跑 `./build.sh` 就会重新出图并压成 `.icns`，不依赖任何设计稿。

构建完成后应用在 `dist/MDay.app`，双击即可运行。装到应用程序目录：

```bash
cp -R dist/MDay.app /Applications/
```

首次启动会走一遍引导：选数据保存位置 → 可选设置打开密码与文件加密。

---

## 使用说明

1. 左侧是导航：今天 / 全部日记 / 那年今日 / 日历 / 统计，下面按日记本、标签分组
2. 中间是日记列表，按天分组；顶部可排序
3. 右边是写作区，直接写 Markdown，不需要按任何保存键
4. `⌘N` 新建，`⌘J` 叫出 AI 助手，`⌘F` 搜索
5. 侧边栏日记本那一栏可以拖动排序，右键能改名、换图标、单独上锁、设为默认

### 快捷键

| 快捷键 | 功能 |
| --- | --- |
| `⌘N` | 新建日记 |
| `⌘⇧N` | 新建九宫格日记 |
| `⌘T` | 回到今天 |
| `⌘F` | 搜索 |
| `⌘J` | 打开 / 收起 AI 助手 |
| `⌘L` | 立即锁定 |
| `⌘,` | 设置 |

编辑器里：`Tab` / `Shift+Tab` 缩进，`⌘Z` 撤销。

---

## 数据存在哪里

默认目录：`~/Documents/日迹日记/`（路径可在设置里更改）

```
日迹日记/
├── journals/<日记本ID>/<年-月-日>/<时间>-<随机>.md   每篇日记一个文件
└── attachments/                                     插入的图片
```

每篇日记都是标准 Markdown，开头一小段元信息：

```markdown
---
id: 3F2A...
journal: 9B80...
created: 2026-09-25T16:21:07+08:00
updated: 2026-09-25T16:24:31+08:00
title: 今天的标题
tags: 日常, 复盘
mood: 🙂
weather: partly|24.7|北京|auto
city: 北京
---

正文 Markdown……
```

用任何编辑器（Typora、VS Code、Obsidian）都能直接打开、编辑。想换电脑，整个文件夹拷过去就行。

设置与密码校验值存在 `~/Library/Application Support/日迹/config.json`，
密钥类的秘密存在同目录的 `vault/` 里（见「安全说明」）。

⚠️ 内部目录名保留了旧名「日迹」，**不要去改** —— 改了等于换了一个 App，配置和保险库都会读不到。

---

## 天气

每篇日记都能记下当天的天气，显示在编辑器顶栏、列表卡片和日历里。

- **自动记录**：新建「今天」的日记时自动抓取，并给今天已有的日记补上；启动 / 解锁时也会补一次
- **手动改**：点顶栏的天气按钮，可以换成晴 / 多云 / 阴 / 小雨 / 雨 / 大雨 / 雷阵雨 / 雪 / 雨夹雪 / 雾 / 霾 / 大风，也可以「不显示天气」。今天的日记多一个「获取当前天气」
- **城市**：`⌘,` → 「天气」里改，默认北京。点「测一下」可立刻验证接口是否通
- **数据来源**：Open-Meteo 免费接口，不需要 API Key，**只发送城市名**，不上传任何日记内容
- **存在哪**：写在自己那篇 `.md` 的 front matter 里，格式 `天气代号|温度|城市|auto或manual`。可以手工改，软件照读

命令行验证天气接口：

```bash
./dist/MDay.app/Contents/MacOS/RiJi --weather 北京
```

---

## AI 怎么配

1. 到 `platform.deepseek.com` 创建一个 API Key
2. App 里按 `⌘,` → 「小迹 AI」→ 粘贴 Key → 点「测试连接」

接口地址默认 DeepSeek，也兼容任何 OpenAI 格式的接口。API Key 存在本机保险库里，不联网、不随文件夹拷贝到别的电脑。

---

## 安全说明

| 机制 | 保护什么 | 透明性 |
| --- | --- | --- |
| 打开密码 | 只锁界面 | 磁盘上仍是明文 Markdown |
| 文件加密 | 正文以 AES-256-GCM 密文写盘 | 离开 App 无法直接阅读 |
| 触控 ID | 免输密码解锁 | 密码存本机保险库 |
| 日记本单独上锁 | 单本内容不对任何人可见 | 未解锁时从所有列表 / 搜索 / 统计 / AI / 导出里排除 |

### 日记本单独上锁

- 上锁的前提是设过**打开密码** —— 校验用的就是那一套，不另设一本子的密码（两个熵源并存，忘一个等于丢一半数据）
- 锁的状态存在 `config.json` 的 `locked` 字段里；「本次已解锁」只活在内存里，**⌘L 或关掉 App 就归零**
- 右键日记本可以「立即重新上锁」—— 把电脑递给别人之前一键关上
- 上锁后 `Store.visible` 会把这本日记全过滤掉，所有读取路径（列表 / 搜索 / 标签统计 / 字数统计 / 日历热力图 / AI 上下文 / JSON 备份）都走它
- 默认日记本锁着时，`⌘N` 会落到第一本还开着的日记本里，不会把新日记写进一个你当场看不见的地方

### 本机保险库

AI API Key 和触控 ID 用的打开密码都存 `~/Library/Application Support/日迹/vault/`，
AES-GCM 加密落盘，权限 `0600`，密钥由主板 UUID + 当前用户 uid 派生（`Vault.swift`）。

把文件单独拷走没用，换台机器也解不开。⚠️ **不要改成系统钥匙串** —— 原因见下面「钥匙串在本地构建的 App 上不可用」。

### 密码无法找回

如果忘记：退出 App，删除 `~/Library/Application Support/日迹/config.json` 可重置密码。
但**如果开了文件加密，日记内容将无法解密**，请务必记好密码。

---

## 农历 / 黄历 / 节假日：数据从哪来

界面里明写了两句免责：黄历宜忌标注「民间传统说法，各流派并不一致，这里只作参考」，
星座运势标注「娱乐向，没有天文或统计依据」。除此之外的都是可复算的，没写死。

| 内容 | 依据 |
| --- | --- |
| 农历月日 | Foundation `Calendar(identifier: .chinese)`，固定东八区 |
| 二十四节气 | Meeus《Astronomical Algorithms》太阳视黄经低精度公式 + 牛顿迭代求黄经 = 15°×n 的时刻 |
| 干支纪日 | **1949-10-01 = 甲子日**（《农历的编算和颁行》规定的循环参考点），按儒略日数取模 60 |
| 干支纪年 | 以**立春**为界，1984 甲子年 |
| 干支纪月 | 五虎遁（甲己之年丙作首） |
| 黄道黑道十二神 | 《协纪辨方书》《玉匣记》口诀「寅申须加子，卯酉却居寅，辰戌龙位上，巳亥午上存，子午临申地，丑未戌相寻」 |
| 建除十二神 | 月建与日支同支为「建」，顺行 |
| 法定节假日与调休 | 国务院办公厅三年通知（[2024](https://www.gov.cn/zhengce/content/202311/content_6911231.htm) / [2025](https://www.gov.cn/zhengce/content/202411/content_6986754.htm) / [2026](https://www.gov.cn/zhengce/content/202511/content_7012345.htm)），共 33 天 |

两个刻意的「不猜」：

- **节假日只收录 2024–2026**。没收录的年份，日历上直接显示不出来，`hasData` 返回 false —— 调休凑出来的安排没法用规律外推，宁可空着
- **星座运势是娱乐向文案**，用 `日期 + 星座序号` 做种子从文案池里选，同一天同一个星座结果稳定。不要当预测用

所有关键数值都固化成了自检断言（立春分界、甲子锚点、青龙口诀、节假日天数、整年 366 天扫描），
改坏了会当场失败。

---

## 深挖：写作区是怎么渲染的

### 单栏即时渲染

不再左右分栏。渲染引擎在 `LiveMarkdown.swift`，**解析**（把文本切成带类型的行）和**属性套用**是分开的两步，
纯函数那部分可以直接被自检覆盖。

关键设计：**光标所在的那一段永远露出源码**。这不只是个视觉细节 —— 如果标记被隐藏了，
用户就没法把光标放进 `**` 中间去删掉一个星号。所以渲染是按「光标位置」实时重算的。

底子仍然是纯 Markdown 文本，工具条右侧可以切「看源码」看原文、「纯预览」看最终排版。

### 渲染排版规格

渲染出来长什么样，由 `MDType.swift` 一份规格统一决定 —— 编辑器的即时渲染、工具条里的「纯预览」、
AI 回复里的 Markdown、导出的渲染，全部读它。

数值不是拍脑袋定的，是把三个开源样式表的规则换算成「相对正文字号的倍率」：

| 来源 | 借了什么 |
| --- | --- |
| [github-markdown-css](https://github.com/sindresorhus/github-markdown-css)（MIT） | 一级二级标题压一条底部横线；表格单元格内边距 6px × 13px、表头底色、隔行斑马纹；行内代码 85% 字号 + 圆角底；引用左侧竖框 + 弱化文字 |
| [@tailwindcss/typography](https://github.com/tailwindlabs/tailwindcss-typography)（MIT） | 正文行高 1.75（比 GitHub 的 1.5 松）；**标题色比正文更深**（#111827 vs #374151）—— 层级不只靠字号；标题「上留白大于下留白」（mt 1.6em / mb 1em） |
| [typora-solarized](https://github.com/belenos/typora-solarized)（MIT） | 长文正文行高 1.8；代码块加细边框把块框出来；引用加底纹而不只是竖线 |

落地成这几条：

- **字号阶梯**：标题 1.58 / 1.32 / 1.15 / 1.05 / 0.97 / 0.92 × 正文；代码 0.88；表格 0.94
- **行高**：正文 1.72、列表与表格 1.48、代码 1.60、标题 1.32
- **留白**：段后 0.64em；标题前 1.05em（叠上前一段的 0.64 ≈ 1.7em，正对 Tailwind 的 mt 1.6em）；标题后 0.42em
- **装饰**（NSTextView 画不出来，由 `RJTextView.draw(_:)` 自绘）：标题底边线、引用圆头竖条、列表真圆点（二级空心）、圆角勾选框、代码块圆角底 + 左强调条、表格斑马纹

因为全是倍率，在设置里改一次正文字号，标题、行高、留白、装饰会整套等比跟着变。

### 写作区样式（`MDStyle`）

上面那套规格抽成了一组可调参数，挂在 `AppSettings.mdStyle` 上：

| 字段 | 含义 |
| --- | --- |
| `preset` | 整体基调：`compact` 紧凑 / `relaxed` 舒展 / `magazine` 杂志，手调后落 `custom` |
| `lineHeight` | 正文行高 1.30–2.20 |
| `paraSpacing` | 段间距 0.20–1.20（单位是「正文字号的倍率」） |
| `headingScale` | 标题字号整体缩放 0.80–1.40 |
| `contentWidth` | 版心宽度，0 = 撑满，否则是点数（820 舒适 / 680 窄） |
| `headingRule` / `tableStripe` / `quoteTint` | 三个装饰开关 |

两个必须守住的约定：

1. **默认值必须严格等于改造前的规格**（`MDStyle.default` → 行高 1.72、段间距 0.64、标题不缩放）。
   自检里有断言守着，老用户升级后观感不能变
2. **块间距是「段落间距的固定倍数」**，不是各自独立的数 —— 所以拖一个滑块，整篇的呼吸感是一起变的。
   `listItemAfter = paraAfter × 0.28`、`codeBlockBefore = paraAfter × 1.09`、
   `dividerBefore = paraAfter × 1.44`、`headingBefore(1) = paraAfter × 1.875` …

⚠️ **量纲别搞混**：`paraAfter` 这一批值在 `MDType` 里**已经乘过 `base` 了，是点数**，用的时候不要再乘一次。
`bodyLine` / `tightLine` / `codeLine` 才是「行高倍率」。

### 改造时踩到的坑

**1. `NSColor.withAlphaComponent(_:)` 是「直接设定」而不是「叠加」。**
颜色本身已经带 0.11 alpha 时，再调 `withAlphaComponent(0.65)` 会得到不透明度 0.65 的黑线 —— 一条深粗线。
所以 `MDInk` 里的 `rule` / `tableLine` 必须定义成**不透明**色，透明度交给调用处控制。

**2. `NSLayoutManager.lineFragmentRect(forGlyphAt:)` 返回「满宽」矩形，不含段落缩进。**
它给的是整行可用的矩形（用于铺背景），而 `headIndent` 只影响 glyph 的实际落点。
所以项目符号、引用竖条、勾选框的位置不能直接拿 `rect.minX` 减偏移算 ——
要另外读 `paragraphStyle.headIndent` 求出文字左边缘，否则会被整块画到视图外面（表现为「装饰全都不见了」）。

**3. 块间距被乘了两次 `base`，整片预览变成空白。**
`MDType` 把 `paraAfter` 从「倍率」改成「点数」之后，`MarkdownView.swift` 里还留着旧写法 `base * t.paraAfter`，
结果一个段落垫出 20 × 20 × 0.64 ≈ 256pt 空白，设置页那张实时预览卡片整片变白。
自检里加了「块间距必须是点数、且不超过 50pt」和「字号翻倍时段间距只翻倍」两条断言把它钉住。

**4. 列表解析会贪婪吞掉后面的待办行。**
`- [ ] 待办` 紧跟在普通列表后面时，列表的消费循环只看 `[-*+]`，会把待办也吃进来，渲染成「圆点 + 字面 `[ ]`」。
现在消费循环碰到任务行就停，列表在待办处断开、待办后面的列表另起一块。

---

## 界面实现

设置页是「左边分类标题 / 右边具体内容」的两栏结构，共 8 页。

界面视觉由 `Theme.swift` 统一管：

- **字号**：一律走 `Font.rj(_:weight:design:)`，它带全局缩放系数。**不要用 `Font.system(size:)`**
- **颜色**：只用 `Color.rjAccent`（暖赤陶）作强调色，随明暗模式自动换；不出现系统蓝
- **按钮**：4 套样式接管全部按钮 —— `RJPrimaryButtonStyle`（唯一实心，只留给主 CTA）、
  `RJSubtleButtonStyle`（浅底描边）、`RJPlainButtonStyle`（纯文字）、`PressableStyle`（按压回弹）
- **图标按钮**：`IconButton` / `MenuIcon` / `MenuPill` / `IconSegmented`

改界面时不要再用 `.borderedProminent`：macOS 26 会给它自动刷一层蓝色 tint，这正是之前「一片蓝按钮」的来源。

### 分栏宽度：AI 面板必须「自己停靠」

AI 面板**不要**用系统的 `.inspector(isPresented:)`。它挂在 `NavigationSplitView` 上时会参与三栏的宽度协商，
一旦总宽不够，系统就把最左边那一栏整栏收走 —— 用户看到的就是「打开 AI 助手，左侧导航栏被挤跑了」。

正确做法是在 `detail:` 里用一个 `HStack`，把面板当成详情栏内部的一块：

```swift
} detail: {
    HStack(spacing: 0) {
        detailColumn
        if showAI {
            PanelResizer(width: $aiPanelWidth, minWidth: 280, maxWidth: 520)
            AIPanel(currentEntryId: selectedId, isPresented: $showAI)
                .frame(width: CGFloat(aiPanelWidth))
        }
    }
}
```

这样它只压缩编辑区，侧边栏和中栏纹丝不动。窗口最小宽度按「侧边栏 226 + 中栏 286 + 编辑区 ~300 + 面板 300」定在 **1120**。

### 编辑区必须能压缩到 300 出头

面板打开后编辑区只剩 300 出头，所以编辑区里的两条横条都不能「硬撑」：

- **工具条**（`toolbarRow`）用四级 `ViewThatFits`：一行 → 两行 → 三行（行内样式 / 段落与插入 / 尾部）→ 横向滚动兜底。
  ⚠️ **关键**：光折成两行不够。「标记」那组自己有 13 个 30pt 的按钮（≈450pt），折完一行依然塞不下，
  此时 `ViewThatFits` 挑不出能放下的分支，会把这一行按原宽硬撑出去，把整个详情栏顶宽 —— 结果还是侧边栏被挤跑。
  必须拆到「四个行内按钮 + 八个段落按钮」这个粒度才够窄
- **顶栏**（`topBar`）同样四级：全量 → 摘掉时间 → 再摘掉日记本名 → 只留天气；右侧操作按钮始终保留

改这些地方时的验证方式：`RJ_WIN=1120x700 … --snapshot /tmp/x`，看侧边栏左边有没有被裁。

### 界面字号

`⌘,` → 「通用」→「界面字号」，四档：紧凑（1.00）/ 标准（1.15）/ 大（1.30）/ 特大（1.46），默认「大」。

改完立刻整体生效，包括侧边栏、列表、编辑器、预览、AI 面板。实现方式是 `MainView` 上挂 `.id(uiScale)` 触发整块重建。

---

## 日记本：起名 / 图标 / 排序 / 上锁

侧边栏「日记本」那一栏是可编辑的。

**新建 / 编辑**：点标题右边的 `＋`，或右键某一本选「编辑日记本…」，弹同一个窗口 ——
改名字、挑颜色、挑图标、勾「单独上锁」，顶部有大预览跟着实时变。
改动先落在 `JournalDraft` 上，按「保存」才写进 `config.json`，按 Esc 等于没动过。名字必填。

**图标只有一个真值来源**：`Journal.symbol` 是 SF Symbol 名。侧边栏、中栏列表、编辑器顶栏、
「移动到其他日记本」菜单都读它，所以四处永远长一个样（`JournalIconBadge`）。
图标库里每个名字都有自检兜着 —— `NSImage(systemSymbolName:)` 取不到就算失败，
名字写错在界面上就是一个空白方块，光看截图不一定发现。

**排序**：数组顺序就是显示顺序，`saveConfig()` 按数组顺序写进 `config.json`。
拖动用 `onDrag` + 自己写的 `DropDelegate`：

- 只有 `DropDelegate` 的 `DropInfo` 才给得出指针在行内的坐标，用它判断「落在行的上半还是下半」，
  上半插到这一行前面、下半插到后面（正好压中线按后面算）
- **不要**用 `List` 的 `.onMove`：它只在 `List` 里生效，而这里是 `ScrollView` + 自定义行，
  换成 `List` 会把现有的悬停 / 选中 / 毛玻璃行样式全部推翻
- 行高是 `GeometryReader` 量出来的（跟着界面缩放会变），不能写死
- 落点提示线画在行的 `.overlay(alignment: .top/.bottom)` 上

重排规则和落点判断抽成了纯函数 `JournalReorder.reorder` / `.dropsBelow`，自检直接覆盖，
UI 那边只负责把事件喂进来。右键菜单里另有「上移 / 下移」作为拖拽之外的第二条路。

**容错解码**：`Journal` 和 `AppSettings` 一样是逐字段解的 —— 缺名字补「未命名日记本」、
颜色不合法退回品牌色、图标为空退回 `bookmark.fill`、连 id 都没有就补一个新的。
日记本列表和密码同在一个 `config.json` 里，整段解码失败会连密码一起丢掉，所以这里不能大意。

---

## 钥匙串在本地构建的 App 上不可用（重要）

这个 App 是 ad-hoc 签名的（`codesign --sign -`）。ad-hoc 没有稳定的证书身份，钥匙串条目 ACL 里
记的「设计需求」就退化成**创建它的那个二进制的 cdhash**。于是每次重新构建，新二进制 cdhash 变了，
去读旧条目就会被系统判定成「另一个程序想读你的机密信息」，SecurityAgent 弹出授权框。
而 `SecItemCopyMatching` 是**同步阻塞**的 —— 弹框一出，调用它的线程永久卡死，
表现成「App 启动即卡死、没有任何输出」（`Store.init()` 里就要读 API Key，所以一启动就中招）。

试过且**实测无效**的绕法（探针在 `/tmp/rj-kcprobe*.swift`，可复现）：

| 写法 | 结果 |
| --- | --- |
| 裸查询 | ★ 卡死 |
| `kSecUseAuthenticationUI = kSecUseAuthenticationUIFail` | ★ 卡死（它只管生物识别授权，管不到 ACL 授权框） |
| `LAContext.interactionNotAllowed`（现代替代写法） | ★ 卡死 |
| `kSecUseDataProtectionKeychain = true` | ◎ 不卡，但写入 `errSecMissingEntitlement (-34018)` —— ad-hoc 签名没有 application-identifier 权限 |

结论：**启动路径上绝不能碰钥匙串**。现在密钥统一走 `Vault`（见「安全说明」）。

旧版本留在钥匙串里的东西可以一次性搬走（会弹一次授权框，所以只在显式执行时跑，并且带超时）：

```bash
./dist/MDay.app/Contents/MacOS/RiJi --recover-key
```

平时不需要跑 —— 用密码解锁时 `Store.rearmBiometricIfNeeded` 会自动把密码补存进保险库，指纹解锁下次就恢复了。

---

## 界面截图（开发用）

```bash
./dist/MDay.app/Contents/MacOS/RiJi --snapshot screenshots
```

App 抓自己的窗口，**不需要屏幕录制权限**，也会顺手带上系统毛玻璃。
截图模式会切到系统临时目录 + 一批示例日记，**绝对不会碰真实日记和 config.json**。

依次拍：主界面 → 深色主界面 → 即时渲染（全语法 / 代码块尾部）→ 纯预览 → 杂志预设 → AI 面板 →
8 个设置页 → 新建 / 编辑日记本弹窗 → 上锁状态与解锁面板 → 九宫格面板 → 日历 → 统计 → 锁屏。

`--snapshot` 必须前台运行（后台跑会被父进程连带杀掉）。

拍弹窗是先把 `store.journalDraft` / `journalGate` 填好再拍的，这样图里能看到完整状态。
拍完一张 sheet 要用 `.rjCloseSettings` 通知让 SwiftUI 自己关 —— 直接调 `NSWindow.endSheet`
只收窗口不改状态，SwiftUI 那边的 `isPresented` 还是 true，接着再弹别的 sheet 会被系统丢掉
（症状是抓到的还是上一张弹窗）。

加环境变量可以强制指定窗口尺寸，用来验证窄宽度下的布局：

```bash
RJ_WIN=1120x700 ./dist/MDay.app/Contents/MacOS/RiJi --snapshot /tmp/rj-narrow
```

注意：返回值是 2 倍视网膜分辨率（1440×840 的窗口出图是 2880×1680）。

---

## 功能自检

```bash
./dist/MDay.app/Contents/MacOS/RiJi --selftest
```

纯计算与内存内往返，不触碰任何真实数据。覆盖：加密往返、Markdown 解析、即时渲染的逐行切分与属性套用、
排版规格（字号阶梯 / 行高 / 装饰标记）、写作区样式的预设与容错解码、日记本的命名 / 图标 / 排序 /
单独上锁 / 容错解码、九宫格模板、列表排序、信纸底纹、写作城市、农历换算、二十四节气、干支纪年纪月纪日、
十二值神、建除、宜忌、节假日（三年逐条核对）、星座运势、每日一句、本机保险库、字数统计、图片路径、
天气编解码、设置容错解码、界面字号缩放等 —— **共 565 项**，任一失败即退出码非 0。

改代码之后请务必跑一遍：`./build.sh && ./dist/MDay.app/Contents/MacOS/RiJi --selftest`。

---

## 项目结构

```
MDay/
├── app/
│   ├── Package.swift                    SwiftPM 清单（macOS 14+）
│   └── Sources/RiJi/
│       ├── App.swift                    入口、主窗口、命令、分栏
│       ├── Models.swift                 数据模型、设置、容错解码
│       ├── Store.swift                  仓库：读写 .md、锁、日记本、加密
│       ├── Crypto.swift                 PBKDF2 / AES-GCM
│       ├── Vault.swift                  本机保险库（替代钥匙串）
│       ├── Biometric.swift              触控 ID / 面容 ID
│       ├── LockView.swift               锁屏与首次引导
│       ├── JournalUnlockView.swift      日记本单独解锁面板
│       ├── JournalEditor.swift          日记本新建 / 编辑弹窗
│       ├── SidebarView.swift            侧边栏
│       ├── EntryListView.swift          中栏列表
│       ├── EditorView.swift             写作区
│       ├── RichEditor.swift             NSTextView 封装
│       ├── LiveMarkdown.swift           即时渲染引擎
│       ├── MDType.swift                 排版规格
│       ├── MarkdownView.swift           预览渲染
│       ├── Paper.swift                  信纸底纹
│       ├── GridJournal.swift            九宫格日记
│       ├── CalendarView.swift           日历与统计
│       ├── Heatmap.swift                写作热力图
│       ├── Almanac.swift                农历 / 节气 / 干支 / 黄历
│       ├── AlmanacView.swift            黄历卡片
│       ├── Holiday.swift                法定节假日与调休
│       ├── Zodiac.swift                 星座与运势
│       ├── DailyAdvice.swift            侧边栏每日一句
│       ├── LifeAdvice.swift             499 条人生建议
│       ├── Weather.swift                Open-Meteo 天气
│       ├── AIPanel.swift / AIService.swift   AI 助手
│       ├── SettingsView.swift           设置（8 页）
│       ├── Export.swift                 导出与备份
│       ├── Theme.swift                  视觉规范与字号缩放
│       ├── SelfTest.swift               565 项自检
│       ├── Snapshot.swift               界面截图
│       └── UIRender.swift               离屏渲染
├── tools/
│   ├── gen_icon.swift                  用 CoreGraphics 画应用图标
│   └── privacy-check.sh                提交前的隐私体检（见下）
├── build.sh                             编译 + 组装 .app + 生成图标 + 签名
├── screenshots/                         界面截图与预览页（本地生成，未入库）
├── .gitignore
└── README.md
```

---

## 提交前：隐私体检

```bash
./tools/privacy-check.sh
```

**每次 push 之前都跑一遍。** 退出码非 0 就先别提交。

为什么需要它：这个仓库里的源码同时是「给用户的示例数据」和「我自己的测试素材」。随手把真实信息
写进单元测试的 fixture、示例日记、设置页的提示文案里，肉眼很难发现 —— 但一旦 push 就公开了，
而 GitHub 上删文件不等于删历史，还得 rewrite。

它检查三类**会被提交**的文件（已跟踪的 + 新增的，自动排除 `.gitignore` 里的）：

| 类别 | 查什么 |
| --- | --- |
| 真实身份 | 昵称、本名、老家地名、家人、同事 / 前雇主、身体数据 |
| 密钥令牌 | `sk-…` / `ghp_…` / `github_pat_…` / `AIza…` / `xox…-` / `Bearer …` / `BEGIN … PRIVATE KEY` |
| 本机信息 | `/Users/<具体用户名>/…`、内网 IP（`10.` / `192.168.` / `172.16–31.`） |

最后会**提示**（但不拦）作者主动公开的信息：`Miki Zhu`、邮箱、GitHub、公众号。
它们本来就该出现在「关于」页和本文档里 —— 提示只是防哪天被误删。

> 反例很重要：脚本自己也有一个关键词表，所以它必须把自己排除掉，否则每次都先举报自己一遍。

### 一个刻意保留的例外

Bundle ID `com.meiling.riji` 里带着作者名字的拼音，但**不改**：

- 它决定 UserDefaults 的归属，以及保险库密钥的派生种子（`Vault.swift` 里的字面量）
- 改了等于换了一个 App —— 已安装用户的界面偏好、AI API Key、指纹解锁密码都会读不到
- 数据目录 `日迹日记/` 同理

权衡之后保留。这类「路径 / 标识必须一致」的东西，动了会真的丢东西，不列入检查。

### 因此形成的一条约定

**示例数据和测试 fixture 必须用中性内容**：城市用「北京 / 上海 / 杭州」，
人名用「张三」，不要写自己真实的生活细节。这样即使有人从源码里读，也读不到任何关于作者的事。

---

## 一份新功能的落地清单

改这个项目时按这个顺序走，能省掉大部分返工：

1. 数据模型加到 `Models.swift`，**新字段一律给默认值**，并在容错 `init(from:)` 里补一行 ——
   否则旧 `config.json` 会整段解码失败，连密码一起丢
2. 逻辑放 `Store.swift`，读路径**默认走 `visible`**（会被日记本锁过滤）
3. 在 `SelfTest.swift` 里补断言，`./build.sh && … --selftest` 必须全绿
4. 需要截图的话在 `Snapshot.swift` 里加一步，跑 `… --snapshot screenshots`
5. `./tools/privacy-check.sh` 过了再 `git commit`

---

## 技术栈

- **Swift / SwiftUI**：全部界面
- **AppKit**：`NSTextView` 富文本编辑、`NSWindow`、菜单、`NSSavePanel`、毛玻璃
- **Foundation**：`Calendar(identifier: .chinese)` 农历、`URLSession` 网络
- **CryptoKit**：PBKDF2 密钥派生、AES-256-GCM
- **LocalAuthentication**：触控 ID / 面容 ID
- **CoreGraphics**：应用图标绘制
- **IOKit**：读取主板 UUID 作为保险库密钥的一部分
- **SwiftPM + swiftc**：命令行构建，无 Xcode 工程依赖

**零第三方依赖。** 没有 `Package.resolved`，没有 CocoaPods，没有 SPM 远程包。

---

## 隐私说明

- 所有日记都是本地 `.md` 文件，**不上传任何服务器**
- 天气请求只发送城市名，不发送日记内容
- AI 对话只在你主动使用时才发出，内容是你选定的上下文范围；API Key 存本机保险库
- 不收集任何统计信息，不联网心跳，不检查更新
- 打开密码、日记本锁、文件加密全部在本机完成，没有任何找回后门

---

## 开发者

**Miki Zhu**

- GitHub：[@mikizhu520](https://github.com/mikizhu520/)
- 邮箱：750856902@qq.com
- 微信公众号：**逍遥小斑鸠**

---

## License

MIT
