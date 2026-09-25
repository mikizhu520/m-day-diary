# MDay · 本地 Markdown 日记本

macOS 原生应用（SwiftUI 编写，非网页套壳）。所有数据保存在你自己的电脑上，不经过任何服务器。

- 已安装位置：`/Applications/MDay.app`
- 工程源码：`app/`（Swift Package）
- 重新编译：在本文件夹执行 `./build.sh`，产物在 `dist/MDay.app`

---

## 数据存在哪里

默认目录：`~/Documents/日迹日记/`

```
日迹日记/
├── journals/<日记本ID>/<年-月-日>/<时间>-<随机>.md   每篇日记一个文件
└── attachments/                                     插入的图片
```

每篇日记都是标准 Markdown 文件，开头是一小段元信息：

```markdown
---
id: 3F2A...
journal: 9B80...
created: 2026-09-25T16:21:07+08:00
updated: 2026-09-25T16:24:31+08:00
title: 今天的标题
tags: 日常, 复盘
favorite: true
mood: 🙂
weather: partly|24.7|北京|auto
---

正文 Markdown……
```

用任何编辑器（Typora、VS Code、Obsidian）都能直接打开、编辑。
想换电脑，整个文件夹拷过去就行。

设置与密码校验值存在 `~/Library/Application Support/日迹/config.json`。
AI 的 API Key 存在 macOS 钥匙串里。

---

## 天气

每篇日记都能记下当天的天气，显示在日记顶栏、列表卡片和日历里。

- **自动记录**：新建「今天」的日记时自动抓取，同时也给今天已有的日记补上。
  启动 / 解锁时如果发现今天的日记还没有天气，会自动补一次。
- **手动改**：点日记顶栏的天气按钮，可以换成晴 / 多云 / 阴 / 小雨 / 雨 / 大雨 / 雷阵雨 /
  雪 / 雨夹雪 / 雾 / 霾 / 大风，也可以「不显示天气」。
  今天的日记多一个「获取当前天气」。
- **城市**：⌘, → 「天气」里改，默认北京。点「测一下」可立刻验证接口是否通。
- **数据来源**：Open-Meteo 免费接口，不需要 API Key，只发送城市名，不上传任何日记内容。
- **存在哪**：写在自己那篇 `.md` 的 front matter 里，格式 `天气代号|温度|城市|auto或manual`。
  例如 `weather: partly|24.7|北京|auto`。可以手工改，软件会照读。

命令行验证天气接口：

```
./dist/MDay.app/Contents/MacOS/RiJi --weather 北京
```

---

## 快捷键

| 快捷键 | 功能 |
| --- | --- |
| ⌘N | 新建日记 |
| ⌘T | 回到今天 |
| ⌘F | 搜索 |
| ⌘J | 打开 / 收起 AI 助手 |
| ⌘L | 立即锁定 |
| ⌘, | 设置 |

编辑器里：`Tab` / `Shift+Tab` 缩进，⌘Z 撤销。

---

## AI 怎么配

1. 到 platform.deepseek.com 创建一个 API Key
2. App 里按 ⌘, → 「小迹 AI」→ 粘贴 Key → 点「测试连接」

接口地址默认是 DeepSeek，也兼容任何 OpenAI 格式的接口（通义、智谱、Kimi、本地 Ollama 都行）。

---

## 安全说明

- **密码锁**：只锁界面，磁盘上仍是明文 Markdown（方便随时用别的工具打开）
- **文件加密**：设置里可开启 AES-256-GCM，开启后日记正文以密文写盘
- **触控 ID 解锁**：⌘, → 「安全与锁」→ 打开「用触控 ID 解锁」，输入一次密码确认即可。
  之后每次锁屏都会自动弹出指纹验证，按一下就能进，不用再输密码。
  密码加密保存在**本机保险库**里（不联网、不随文件夹拷贝到别的电脑，换台机器解不开）。
- **本机保险库（`Vault.swift`）**：AI API Key 和触控 ID 用的打开密码都存这里 ——
  AES-GCM 加密落盘在 `~/Library/Application Support/日迹/vault/`，权限 0600，
  密钥由主板 UUID + 当前用户 uid 派生。**不要改成系统钥匙串**，原因见下面「钥匙串在本地构建的 App 上不可用」。
- ⚠️ 密码无法找回。如果忘记：退出 App，删除 `~/Library/Application Support/日迹/config.json` 可重置密码；但**如果开了加密，日记内容将无法解密**，请务必记好密码。

---

## 写作区：单栏即时渲染

不再左右分栏。写的是 Markdown 语法，看到的是排好版的日记：

- 敲 `# 标题` → 当场变大变粗，`#` 自己消失
- 敲 `**加粗**`、`*斜体*`、`~~删除线~~`、`` `行内代码` ``、`[链接](url)` → 当场生效，标记同时隐去
- `> 引用`、`- 列表`、`1. 有序`、`- [ ] 待办`、表格、代码块、`---` 分割线同样当场渲染
- **光标回到哪一行，那一行的语法就重新露出来**，方便直接改；光标移开又收回去

底子仍然是纯 Markdown 文本 —— 工具条右侧可以切「看源码」看原文、「纯预览」看最终排版，
文件另存出去用任何编辑器都能打开。

渲染引擎在 `app/Sources/RiJi/LiveMarkdown.swift`（解析与属性应用分开，纯函数部分可直接被自检覆盖），
编辑器封装是 `RichEditor.swift` 里的 `RichTextEditor`。

---

## 渲染排版规格

渲染出来的内容长什么样，由 `app/Sources/RiJi/MDType.swift` 这一份规格统一决定 ——
编辑器的即时渲染、工具条里的「纯预览」、AI 回复里的 Markdown、导出的渲染，全部读它。

数值不是拍脑袋定的，是把三个开源样式表的规则换算成「相对正文字号的倍率」：

| 来源 | 借了什么 |
| --- | --- |
| [github-markdown-css](https://github.com/sindresorhus/github-markdown-css)（MIT） | 一级二级标题压一条底部横线；表格单元格内边距 6px × 13px、表头底色、隔行斑马纹；行内代码 85% 字号 + 圆角底；引用左侧竖框 + 弱化文字 |
| [@tailwindcss/typography](https://github.com/tailwindlabs/tailwindcss-typography)（MIT） | 正文行高 1.75（比 GitHub 的 1.5 松）；**标题色比正文更深**（#111827 vs #374151）——层级不只靠字号；标题「上留白大于下留白」（mt 1.6em / mb 1em） |
| [typora-solarized](https://github.com/belenos/typora-solarized)（MIT） | 长文正文行高 1.8；代码块加细边框把块框出来；引用加底纹而不只是竖线 |

落地成这几条：

- **字号阶梯**：标题 1.58 / 1.32 / 1.15 / 1.05 / 0.97 / 0.92 × 正文；代码 0.88；表格 0.94
- **行高**：正文 1.72、列表与表格 1.48、代码 1.60、标题 1.32
- **留白**：段后 0.64em；标题前 1.05em（叠上前一段的 0.64 ≈ 1.7em，正对 Tailwind 的 mt 1.6em）；标题后 0.42em
- **装饰**（NSTextView 画不出来，由 `RJTextView.draw(_:)` 自绘）：标题底边线、引用圆头竖条、列表真圆点（二级空心）、圆角勾选框、代码块圆角底 + 左强调条、表格斑马纹

因为全是倍率，在设置里改一次正文字号，标题、行高、留白、装饰会整套等比跟着变。

### 写作区样式可以在设置里调（`MDStyle`）

上面那套规格原本写死在 `MDType` 里，现在抽成一份可调参数 `MDStyle`，挂在 `AppSettings.mdStyle` 上：

| 字段 | 含义 |
| --- | --- |
| `preset` | 整体基调：`compact` 紧凑 / `relaxed` 舒展 / `magazine` 杂志，手调后落 `custom` |
| `lineHeight` | 正文行高 1.30–2.20 |
| `paraSpacing` | 段间距 0.20–1.20（单位是「正文字号的倍率） |
| `headingScale` | 标题字号整体缩放 0.80–1.40 |
| `contentWidth` | 版心宽度，0 = 撑满，否则是点数（820 舒适 / 680 窄） |
| `headingRule` / `tableStripe` / `quoteTint` | 三个装饰开关 |

两个必须守住的约定：

1. **默认值必须严格等于改造前的规格**（`MDStyle.default` → 行高 1.72、段间距 0.64、标题不缩放）。
   自检里有断言守着，老用户升级后观感不能变。
2. **块间距是「段落间距的固定倍数」**，不是各自独立的数 —— 所以拖一个滑块，
   整篇的呼吸感是一起变的。`listItemAfter = paraAfter × 0.28`、`codeBlockBefore = paraAfter × 1.09`、
   `dividerBefore = paraAfter × 1.44`、`headingBefore(1) = paraAfter × 1.875` …

⚠️ **量纲别搞混**（这个坑真踩过，见下面第 3 条）：`paraAfter` 这一批值在 `MDType` 里
**已经乘过 `base` 了，是点数**，用的时候不要再乘一次 `base`。
`bodyLine` / `tightLine` / `codeLine` 才是「行高倍率」，配合 `leading(size:multiple:)` 用。

### 改造时踩到的几个坑

**1. `NSColor.withAlphaComponent(_:)` 是「直接设定」而不是「叠加」。**
如果颜色本身已经带 0.11 的 alpha，再调 `withAlphaComponent(0.65)` 会得到不透明度 0.65 的黑线 —— 一条深粗线。
所以 `MDInk` 里的 `rule` / `tableLine` 必须定义成**不透明**色，透明度交给调用处控制。

**2. `NSLayoutManager.lineFragmentRect(forGlyphAt:)` 返回的是「满宽」矩形，不含段落缩进。**
它给的是整行可用的矩形（用于铺背景），而 `headIndent` 只影响 glyph 的实际落点。
所以项目符号、引用竖条、勾选框的位置不能直接拿 `rect.minX` 减偏移算 ——
要另外读 `paragraphStyle.headIndent` 求出文字左边缘，否则会被整块画到视图外面（表现为「装饰全都不见了」）。

**3. 块间距被乘了两次 `base`，整片预览变成空白。**
`MDType` 把 `paraAfter` 这批值从「倍率」改成「点数」之后，`MarkdownView.swift` 里还留着旧写法
`base * t.paraAfter`，结果一个段落垫出 20 × 20 × 0.64 ≈ 256pt 空白，设置页那张实时预览卡片
整片变成空白（高度是对的，内容被推到看不见的地方）。
自检里加了「块间距必须是点数、且不超过 50pt」和「字号翻倍时段间距只翻倍」两条断言把它钉住。

**4. 列表解析会贪婪吞掉后面的待办行。**
`- [ ] 待办` 紧跟在普通列表后面时，列表的消费循环只看 `[-*+]`，会把待办也吃进来，
渲染成「圆点 + 字面 `[ ]`」。现在消费循环碰到任务行就停，列表在待办处断开、待办后面的列表另起一块
（自检有断言）。

### 钥匙串在本地构建的 App 上不可用（重要）

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

```
./dist/MDay.app/Contents/MacOS/RiJi --recover-key
```

平时不需要跑 —— 用密码解锁时 `Store.rearmBiometricIfNeeded` 会自动把密码补存进保险库，
指纹解锁下次就恢复了。

---

## 日记本：起名 / 图标 / 排序

侧边栏「日记本」那一栏是可编辑的。

**新建 / 编辑**：点标题右边的 `＋`，或右键某一本选「编辑日记本…」，弹同一个窗口 ——
改名字、从 12 个颜色里挑一个、从 48 个图标（分「记录 / 工作 / 生活 / 健康 / 心情 / 学习」六组）里挑一个，
顶部有大预览跟着实时变。改动先落在 `JournalDraft` 上，按「保存」才写进 `config.json`，按 Esc 等于没动过。

名字是必填的：空名字时保存按钮是灰的，免得侧边栏冒出一堆「未命名」。

**改名安全**：`Journal.name` 和 `id` 是分开的。磁盘上的目录是 `journals/<id>/…`，改名只动 `name`，
所以已有日记一篇都不会丢、也不会被搬来搬去。

**图标只有一个真值来源**：`Journal.symbol` 是 SF Symbol 名。侧边栏、中栏列表、编辑器顶栏、
「移动到其他日记本」菜单都是读它，所以四处永远长一个样（`JournalIconBadge`）。
图标库里每一个名字都有自检兜着 —— `NSImage(systemSymbolName:)` 取不到就算失败，
名字写错在界面上就是一个空白方块，光看截图不一定发现。

**排序**：数组顺序就是显示顺序，`Store.saveConfig()` 按数组顺序写进 `config.json`。
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

## 界面

设置页是「左边分类标题 / 右边具体内容」的两栏结构，共 7 页：写作区、通用、安全与锁、小迹 AI、天气、数据与备份、关于。

界面视觉由 `app/Sources/RiJi/Theme.swift` 统一管：

- **字号**：一律走 `Font.rj(_:weight:design:)`，它带全局缩放系数，不要用 `Font.system(size:)`
- **颜色**：只用 `Color.rjAccent`（暖赤陶）作强调色，随明暗模式自动换；不出现系统蓝
- **按钮**：4 套样式接管全部按钮 —— `RJPrimaryButtonStyle`（唯一实心，只留给主 CTA）、
  `RJSubtleButtonStyle`（浅底描边）、`RJPlainButtonStyle`（纯文字）、`PressableStyle`（按压回弹）
- **图标按钮**：`IconButton` / `MenuIcon` / `MenuPill` / `IconSegmented`

改界面时不要再用 `.borderedProminent`：macOS 26 会给它自动刷一层蓝色 tint，这正是之前「一片蓝按钮」的来源。

### 分栏宽度：AI 面板必须「自己停靠」

AI 面板**不要**用系统的 `.inspector(isPresented:)`。它挂在 `NavigationSplitView` 上时会参与三栏的
宽度协商，一旦总宽不够，系统就把最左边那一栏整栏收走 —— 用户看到的就是「打开 AI 助手，左侧导航栏被挤跑了」。

正确做法是在 `detail:` 里用一个 `HStack`，把面板当成详情栏内部的一块：

```swift
} detail: {
    HStack(spacing: 0) {
        detailColumn.toolbar { /* ... */ }
        if showAI {
            Divider()
            AIPanel(currentEntryId: selectedId, isPresented: $showAI)
                .frame(minWidth: 300, idealWidth: 380, maxWidth: 480)
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
  必须拆到「四个行内按钮 + 八个段落按钮」这个粒度才够窄。
- **顶栏**（`topBar`）同样四级：全量 → 摘掉时间 → 再摘掉日记本名 → 只留天气；右侧 4 个操作按钮始终保留。

改这些地方时的验证方式：`RJ_WIN=1120x700 RIji --snapshot /tmp/x`，看侧边栏左边有没有被裁。

---

## 界面字号

⌘, → 「通用」→「界面字号」，四档：紧凑（1.00）/ 标准（1.15）/ 大（1.30）/ 特大（1.46）。

默认是「大」（1.30）。改完立刻整体生效，包括侧边栏、列表、编辑器、预览、AI 面板。
「编辑器正文字号」滑块可以再单独微调写作区里的正文大小。

---

## 界面截图（开发用）

```
./dist/MDay.app/Contents/MacOS/RiJi --snapshot /tmp/rj-ui
```

App 抓自己的窗口，**不需要屏幕录制权限**，也会顺手带上系统毛玻璃。
截图模式会切到系统临时目录 + 一批示例日记，**绝对不会碰真实日记和 config.json**。

依次拍：主界面 → 深色主界面 → 即时渲染（全语法 / 代码块）→ 纯预览 → 杂志预设 → AI 面板 →
7 个设置页 → 新建 / 编辑日记本弹窗 → 日历 → 统计 → 锁屏，共 19 张。
`--snapshot` 必须前台运行（后台跑会被父进程连带杀掉）。

拍弹窗的那两张是先把 `store.journalDraft` 填好再拍的，这样图里能看到「名字 + 颜色 + 图标选中」的完整状态。
拍完一张 sheet 要用 `.rjCloseSettings` 通知让 SwiftUI 自己关 —— 直接调 `NSWindow.endSheet`
只收窗口不改状态，SwiftUI 那边的 `isPresented` 还是 true，接着再弹别的 sheet 会被系统丢掉
（症状是抓到的还是上一张弹窗）。

加环境变量可以强制指定窗口尺寸，用来验证窄宽度下的布局（比如检查 AI 面板会不会挤跑侧边栏）：

```
RJ_WIN=1120x700 ./dist/MDay.app/Contents/MacOS/RiJi --snapshot /tmp/rj-narrow
```

注意：返回值是 2 倍视网膜分辨率（1440×840 的窗口出图是 2880×1680）。

---

## 功能自检

```
./dist/MDay.app/Contents/MacOS/RiJi --selftest
```

会检查加密往返、Markdown 解析、即时渲染的逐行切分与属性套用、排版规格（字号阶梯 / 行高 / 装饰标记）、
写作区样式的预设与容错解码、日记本的命名 / 图标 / 排序 / 容错解码、本机保险库的加解密与权限、
字数统计、图片路径、天气编解码与 WMO 映射、设置容错解码、字号缩放等 **298 项**，用来确认没有回归。
