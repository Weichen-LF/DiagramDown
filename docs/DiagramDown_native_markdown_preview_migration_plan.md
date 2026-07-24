# DiagramDown 原生 Markdown 预览迁移方案

**目标读者：** Codex / DiagramDown 实现者  
**适用基线：** DiagramDown `0.22.x`，macOS 15+，Apple Silicon  
**文档状态：** Implementation-ready  
**核心目标：** 将当前基于 `WKWebView + markdown-it + highlight.js` 的可见预览迁移为 `swift-markdown AST + SwiftUI` 原生预览；代码高亮迁移到 Tree-sitter；D2 保持原生 CLI；Mermaid 隔离为只负责“源码转 SVG”的隐藏渲染服务。

---

## 1. 执行摘要

当前预览链路为：

```text
Markdown
    ↓
Swift -> WKWebView
    ↓
markdown-it
    ↓
HTML DOM
    ├── highlight.js
    ├── Mermaid.js -> SVG
    └── D2 bridge -> Swift D2 CLI -> SVG
```

目标链路为：

```text
Markdown
    ↓
swift-markdown
    ↓
PreviewDocument
    ↓
SwiftUI Native Preview
    ├── Native text / list / table / image views
    ├── Tree-sitter -> AttributedString
    ├── D2RenderService -> sanitized SVG
    └── MermaidRenderService -> sanitized SVG
```

其中：

- **Markdown 解析：** `swiftlang/swift-markdown`
- **可见预览：** SwiftUI 原生 View
- **代码高亮：** `tree-sitter/swift-tree-sitter` + 选定语言 grammar
- **SVG 显示：** 抽象为 `SVGRendering`，首个实现使用 `exyte/SVGView`
- **D2：** 保留现有 `D2RenderService` 和原生 D2 CLI
- **Mermaid：** 保留 Mermaid.js，但仅运行在一个应用级、不可见、持久化的 `WKWebView` 中；该 WebView 不参与 Markdown 布局和可见预览
- **PDF 导出：** 改为 `NSHostingView + NSPrintOperation` 原生打印管线
- **滚动同步：** 使用 AST source range、SwiftUI layout anchors 和插值计算实现
- **迁移策略：** 旧管线和新管线在开发期并存，通过 feature flag 切换；达到功能和性能验收后删除旧 Markdown Web 预览

最终状态允许应用仍存在一个仅供 Mermaid 使用的隐藏 WebKit 内容进程，但可见预览、Markdown、代码高亮、D2、交互、主题和 PDF 均不再依赖 HTML DOM。

---

## 2. 目标

### 2.1 必须实现

1. 使用 `swift-markdown` 将 Markdown 解析为 AST。
2. 将 AST 转换为稳定的中间模型 `PreviewDocument`。
3. 使用 SwiftUI 原生渲染：
   - 标题
   - 段落
   - 粗体、斜体、删除线
   - 行内代码
   - 链接
   - 图片
   - 引用
   - 有序列表
   - 无序列表
   - 任务列表
   - 表格
   - 代码块
   - 分隔线
4. 使用 Tree-sitter 原生高亮 fenced code block。
5. 保留 Mermaid fenced block，并以 SVG 形式嵌入原生预览。
6. 保留 D2 fenced block，并以 SVG 形式嵌入原生预览。
7. 保留以下现有功能：
   - 编辑器与预览双向滚动同步
   - 点击预览定位源码
   - 每个文件独立的预览滚动状态
   - 50%–200% 预览缩放
   - DiagramDown / GitHub / Paper 主题
   - Light / Dark / Follow System 外观
   - Mermaid light/dark theme
   - D2 layout/theme/padding/sketch 设置
   - Mermaid/D2 inline error
   - Mermaid/D2 focused viewer
   - Mermaid/D2 SVG 导出
   - 全文分页 PDF 导出
   - D2 内存和磁盘缓存
   - 图表稳定 block identity
8. 不允许 Markdown 原始 HTML 执行。
9. Markdown 正文和代码高亮不得依赖 JavaScriptCore、markdown-it、highlight.js 或 Prism。
10. 保持离线、沙箱和文档隐私属性。

### 2.2 性能目标

1. 普通 Markdown 首次预览不再等待 WebKit 页面初始化。
2. Markdown 解析、高亮和图表渲染不得阻塞主线程。
3. 未变化的代码块和图表不得重复解析或渲染。
4. 大文档使用 `LazyVStack`，避免一次创建全部可见 View。
5. 可见预览不持有 HTML DOM 或 CSSOM。
6. 对不含 Mermaid 的普通文档，应用整体内存应较旧管线下降；具体幅度以迁移前基线为准。
7. 主线程上不得出现可重复复现的、由 Markdown parse 或 Tree-sitter parse 导致的长任务。

---

## 3. 非目标

本迁移不包含：

- 所见即所得编辑
- 重写 Mermaid parser 或 layout engine
- 完全移除应用中的所有 WebKit 代码
- 第一阶段支持 Tree-sitter 的全部语言
- 编辑器本身的 Markdown 语法高亮重构
- LSP semantic highlighting
- Markdown 增量 parser
- HTML/CSS 插件系统
- 任意远程图片自动加载
- 远程 Mermaid/Kroki 渲染服务
- Chromium、Puppeteer 或 `mermaid-cli` 打包
- 修改现有 Markdown 文件格式

Mermaid 的隐藏 WebKit 服务是当前架构中允许保留的唯一 WebKit 使用场景。

---

## 4. 当前实现基线

当前相关文件包括：

```text
Mark/
├── MarkdownPreviewView.swift
├── ScrollSyncState.swift
├── D2RenderService.swift
├── PreviewSettingsView.swift
├── PreviewCommands.swift
├── Resources/
│   └── Preview/
│       ├── preview.html
│       ├── preview.css
│       ├── preview.js
│       ├── markdown-it.min.js
│       ├── highlight.min.js
│       └── mermaid.min.js
└── ...

Tests/
└── PreviewRuntimeTests.mjs
```

当前关键行为：

- `MarkdownPreviewView` 创建持久化 `WKWebView`
- Swift 通过 `callAsyncJavaScript` 调用 `window.previewRuntime.renderMarkdown`
- `markdown-it` 生成 HTML
- `highlight.js` 生成代码高亮 HTML
- Mermaid.js 在页面中生成 SVG
- D2 通过 `WKScriptMessageHandler` 请求 Swift 原生渲染
- JS DOM 保存 source-line anchors
- PDF 从 WKWebView 导出
- SVG 从 DOM 中序列化

这些能力必须先被新管线覆盖，再删除旧实现。

---

## 5. 目标架构

```text
Workspace file buffer
        │
        │ Markdown String + revision
        ▼
MarkdownPreviewPipeline
        │
        ├── MarkdownParserService actor
        │       └── swift-markdown
        │
        ├── PreviewDocumentReconciler
        │       └── stable block IDs
        │
        └── PreviewDocument
                │
                ▼
        NativeMarkdownPreviewView
                │
                ├── Native block views
                │
                ├── CodeHighlightService
                │       └── swift-tree-sitter
                │
                ├── DiagramRenderCoordinator
                │       ├── D2RenderService
                │       └── MermaidRenderService
                │
                ├── NativeSVGView
                │       └── SVGRendering backend
                │
                ├── PreviewScrollCoordinator
                └── NativePDFExportService
```

### 5.1 并发边界

- `@MainActor`
  - SwiftUI state
  - `WKWebView` host for Mermaid
  - Save panels
  - `NSPrintOperation`
- actor
  - `MarkdownParserService`
  - `TreeSitterCodeHighlighter`
  - `DiagramRenderCoordinator`
  - `MermaidRenderService`
  - 现有 `D2RenderService`
  - caches
- background task
  - AST 转换
  - Tree-sitter parse/query
  - SVG sanitation
  - digest/hash
  - cache I/O

不要在 SwiftUI `body` 中解析 Markdown、执行 Tree-sitter 或处理 SVG XML。

---

## 6. 依赖决策

### 6.1 新增依赖

#### Markdown

```swift
.package(
    url: "https://github.com/swiftlang/swift-markdown.git",
    exact: "<validated-version>"
)
```

使用产品：

```swift
.product(name: "Markdown", package: "swift-markdown")
```

#### Tree-sitter Swift wrapper

```swift
.package(
    url: "https://github.com/tree-sitter/swift-tree-sitter.git",
    exact: "<validated-version>"
)
```

优先使用：

```swift
.product(name: "SwiftTreeSitter", package: "swift-tree-sitter")
.product(name: "SwiftTreeSitterLayer", package: "swift-tree-sitter")
```

#### Native SVG

```swift
.package(
    url: "https://github.com/exyte/SVGView.git",
    exact: "<validated-version>"
)
```

使用产品：

```swift
.product(name: "SVGView", package: "SVGView")
```

### 6.2 Tree-sitter grammars

第一批支持以下语言：

```text
plain text
bash / shell / sh / zsh
c
cpp / c++
css
diff
dockerfile
go / golang
html
java
javascript / js / jsx
json
lua
python / py
rust / rs
sql
swift
typescript / ts / tsx
yaml / yml
```

grammar 接入规则：

1. 上游有稳定 SwiftPM package 和 tag 时，使用 SwiftPM。
2. 上游只有不稳定 branch 时：
   - pin exact commit；或
   - vendor 生成的 `parser.c`、可选 `scanner.c` 和 query 文件。
3. 不允许依赖 floating `main`。
4. 每个 grammar 必须包含：
   - parser
   - `highlights.scm`
   - 必要时的 `injections.scm`
5. 每个 grammar 的许可证必须加入打包验证。
6. grammar 版本必须进入高亮 cache key。

建议建立统一目录：

```text
Vendor/
└── TreeSitterLanguages/
    ├── TreeSitterBash/
    ├── TreeSitterC/
    ├── TreeSitterCPP/
    ├── TreeSitterCSS/
    ├── TreeSitterDiff/
    ├── TreeSitterDockerfile/
    ├── TreeSitterGo/
    ├── TreeSitterHTML/
    ├── TreeSitterJava/
    ├── TreeSitterJavaScript/
    ├── TreeSitterJSON/
    ├── TreeSitterLua/
    ├── TreeSitterPython/
    ├── TreeSitterRust/
    ├── TreeSitterSQL/
    ├── TreeSitterSwift/
    ├── TreeSitterTypeScript/
    └── TreeSitterYAML/
```

若一次加入全部 grammar 导致包体或构建时间不可接受，按以下顺序分批：

1. Swift、Lua、JavaScript、TypeScript、JSON、YAML、Bash
2. Python、Go、Rust、Java、SQL
3. C、C++、HTML、CSS、Dockerfile、Diff

### 6.3 明确不采用

- MarkdownUI：不作为核心渲染器
- Textual：不作为核心渲染器；其内置代码高亮仍使用 Prism/JavaScriptCore
- HighlightSwift：不采用；使用 highlight.js/JavaScriptCore
- Highlightr：不采用；使用 highlight.js/JavaScriptCore
- Splash：仅适合 Swift，不作为通用高亮方案
- SwiftSyntax：过重且仅适用于 Swift
- Neon：当前不用于只读预览；未来若重构 `NSTextView` 编辑器实时高亮，可以再评估

---

## 7. 新目录结构

建议将预览代码从单一文件拆分：

```text
Mark/
├── Preview/
│   ├── Model/
│   │   ├── PreviewDocument.swift
│   │   ├── PreviewBlock.swift
│   │   ├── PreviewInline.swift
│   │   ├── PreviewSourceRange.swift
│   │   └── PreviewBlockID.swift
│   │
│   ├── Parsing/
│   │   ├── MarkdownParserService.swift
│   │   ├── MarkdownPreviewVisitor.swift
│   │   ├── PreviewDocumentReconciler.swift
│   │   └── PreviewResourceResolver.swift
│   │
│   ├── Rendering/
│   │   ├── NativeMarkdownPreviewView.swift
│   │   ├── PreviewBlockView.swift
│   │   ├── PreviewInlineView.swift
│   │   ├── HeadingBlockView.swift
│   │   ├── ParagraphBlockView.swift
│   │   ├── BlockQuoteView.swift
│   │   ├── ListBlockView.swift
│   │   ├── TableBlockView.swift
│   │   ├── CodeBlockView.swift
│   │   ├── DiagramBlockView.swift
│   │   ├── PreviewImageView.swift
│   │   └── HorizontalRuleView.swift
│   │
│   ├── Highlighting/
│   │   ├── CodeHighlighting.swift
│   │   ├── TreeSitterCodeHighlighter.swift
│   │   ├── TreeSitterLanguageRegistry.swift
│   │   ├── CodeLanguage.swift
│   │   ├── SyntaxToken.swift
│   │   ├── SyntaxCaptureNormalizer.swift
│   │   ├── CodeTheme.swift
│   │   └── CodeHighlightCache.swift
│   │
│   ├── Diagrams/
│   │   ├── DiagramRenderCoordinator.swift
│   │   ├── DiagramBlockState.swift
│   │   ├── DiagramCache.swift
│   │   ├── MermaidRenderService.swift
│   │   ├── MermaidWebViewHost.swift
│   │   ├── SVGDocument.swift
│   │   ├── SVGSanitizer.swift
│   │   ├── SVGRendering.swift
│   │   ├── SVGViewRenderer.swift
│   │   ├── NativeSVGView.swift
│   │   └── DiagramViewerView.swift
│   │
│   ├── Scrolling/
│   │   ├── PreviewScrollCoordinator.swift
│   │   ├── PreviewBlockGeometry.swift
│   │   └── PreviewBlockGeometryPreferenceKey.swift
│   │
│   ├── Theme/
│   │   ├── PreviewTheme.swift
│   │   ├── PreviewMetrics.swift
│   │   ├── DiagramDownPreviewTheme.swift
│   │   ├── GitHubPreviewTheme.swift
│   │   └── PaperPreviewTheme.swift
│   │
│   ├── Export/
│   │   ├── PreviewExportSnapshot.swift
│   │   ├── NativePDFExportService.swift
│   │   └── NativePrintablePreviewView.swift
│   │
│   └── Migration/
│       └── PreviewFeatureFlags.swift
│
├── Resources/
│   └── MermaidRenderer/
│       ├── renderer.html
│       ├── renderer.js
│       └── mermaid.min.js
│
├── MarkdownPreviewView.swift
├── D2RenderService.swift
├── ScrollSyncState.swift
└── ...
```

迁移完成后，`MarkdownPreviewView.swift` 可以保留为入口 facade，内部改为调用 `NativeMarkdownPreviewView`，以减少上层调用点变化。

---

## 8. 中间模型

不要让 SwiftUI View 直接遍历 `swift-markdown` AST。先转换成应用自己的稳定模型。

### 8.1 Source range

```swift
struct PreviewSourceRange: Hashable, Sendable {
    let startLine: Int
    let startColumn: Int
    let endLine: Int
    let endColumn: Int
}
```

要求：

- 行号使用 1-based，保持与现有 scroll bridge 一致。
- 对没有 range 的节点，从最近父节点继承。
- range 必须经过边界校验。
- 最大允许行号维持现有安全边界。

### 8.2 Stable block ID

```swift
struct PreviewBlockID: Hashable, Sendable, Identifiable {
    let rawValue: String
    var id: String { rawValue }
}
```

不要仅使用当前起始行号作为 ID，因为在文档顶部插入文本会使所有后续 ID 改变。

初始 fingerprint：

```text
block kind
+ normalized content
+ language/config where applicable
+ local occurrence index
```

随后通过 `PreviewDocumentReconciler` 与上一 revision 对齐：

1. 相同 fingerprint 且位置接近：复用旧 ID。
2. fingerprint 改变但 block kind 相同且 source range 重叠：复用旧 ID。
3. 列表和表格优先按父节点及相邻 sibling 对齐。
4. 找不到对应项时分配新 ID。
5. 一个旧 ID 不得复用给多个新 block。

该 reconcile 是避免图表闪烁、保持滚动和减少 SwiftUI diff 的关键。

### 8.3 PreviewDocument

```swift
struct PreviewDocument: Equatable, Sendable {
    let revision: UInt64
    let sourceDigest: String
    let blocks: [PreviewBlock]
    let lineCount: Int
}
```

### 8.4 PreviewBlock

```swift
struct PreviewBlock: Identifiable, Equatable, Sendable {
    let id: PreviewBlockID
    let sourceRange: PreviewSourceRange
    let content: PreviewBlockContent
}
```

```swift
enum PreviewBlockContent: Equatable, Sendable {
    case heading(level: Int, inline: PreviewInlineContent)
    case paragraph(PreviewInlineContent)
    case blockQuote([PreviewBlock])
    case unorderedList(items: [PreviewListItem])
    case orderedList(start: Int, items: [PreviewListItem])
    case table(PreviewTable)
    case code(language: CodeLanguage?, rawLanguage: String?, source: String)
    case mermaid(source: String)
    case d2(source: String)
    case thematicBreak
    case image(PreviewImage)
}
```

### 8.5 Inline model

```swift
struct PreviewInlineContent: Equatable, Sendable {
    let nodes: [PreviewInlineNode]
}
```

```swift
indirect enum PreviewInlineNode: Equatable, Sendable {
    case text(String)
    case emphasis([PreviewInlineNode])
    case strong([PreviewInlineNode])
    case strikethrough([PreviewInlineNode])
    case code(String)
    case link(destination: String, title: String?, children: [PreviewInlineNode])
    case image(source: String, title: String?, alt: String)
    case softBreak
    case hardBreak
}
```

使用中间模型而不是直接缓存主题化 `AttributedString`，以便主题、缩放和外观变化时不重新解析 Markdown。

---

## 9. Markdown parser

### 9.1 Service API

```swift
actor MarkdownParserService {
    func parse(
        source: String,
        revision: UInt64,
        previous: PreviewDocument?
    ) async throws -> PreviewDocument
}
```

### 9.2 Pipeline

```text
source validation
    ↓
Document(parsing:)
    ↓
MarkdownPreviewVisitor
    ↓
unreconciled blocks
    ↓
PreviewDocumentReconciler
    ↓
PreviewDocument
```

### 9.3 更新策略

- 保留当前约 150 ms debounce；可通过 benchmark 调整到 80–150 ms。
- 每个文件只保留一个 active parse task。
- 新 revision 到来时取消旧任务。
- 结果应用前检查 revision。
- parse 不在 MainActor 运行。
- parse error 不应清空上一版成功预览；显示轻量错误状态并继续保留旧内容。

### 9.4 Markdown 行为

必须与旧预览保持以下安全语义：

- Raw HTML：不执行，不生成原生 HTML view。
- 未支持 HTML 节点：作为纯文本显示或明确忽略，但必须有测试。
- 链接协议只允许：
  - `http`
  - `https`
  - `mailto`
- 不允许 `javascript:`、`data:text/html` 等可执行协议。
- 图片默认仅允许：
  - workspace 内的相对路径
  - 应用 bundle 示例资源
  - 明确允许的 `data:image/...`
- 不默认加载远程图片。
- workspace 图片路径必须经过：
  - canonicalization
  - workspace root containment check
  - symbolic link policy
  - file size limit
  - supported type check

### 9.5 Fenced code block

```swift
mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> [PreviewBlock] {
    let rawLanguage = codeBlock.language?.trimmingCharacters(
        in: .whitespacesAndNewlines
    )
    let language = CodeLanguage.resolve(rawLanguage)

    switch language {
    case .mermaid:
        return [.mermaid(...)]
    case .d2:
        return [.d2(...)]
    default:
        return [.code(...)]
    }
}
```

不要让 Mermaid/D2 进入 Tree-sitter 高亮服务。

---

## 10. SwiftUI 原生预览

### 10.1 Root view

```swift
struct NativeMarkdownPreviewView: View {
    let document: PreviewDocument
    let configuration: PreviewConfiguration
    let zoom: Int
    let controller: PreviewController

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: metrics.blockSpacing) {
                    ForEach(document.blocks) { block in
                        PreviewBlockView(block: block)
                            .id(block.id)
                            .background(
                                PreviewBlockGeometryReporter(block: block)
                            )
                    }
                }
                .padding(metrics.documentInsets)
            }
        }
    }
}
```

### 10.2 View requirements

- 文本可选择：`.textSelection(.enabled)`
- 链接点击由应用统一打开，不依赖 SwiftUI 自动接受任意 scheme。
- 代码块水平滚动。
- 表格允许水平滚动，列宽尽量稳定。
- 大图片按容器宽度缩放。
- 任务列表在预览中只读。
- 列表支持嵌套。
- blockquote 支持嵌套 block。
- 所有 block 必须带 source range，用于点击定位和滚动同步。
- 交互按钮不能污染 PDF 输出。
- `LazyVStack` 只用于屏幕预览；PDF 使用非 lazy 的打印 view。

### 10.3 Inline rendering

将 `PreviewInlineContent` 转换为 `AttributedString`：

```swift
struct InlineAttributedStringBuilder {
    func build(
        _ content: PreviewInlineContent,
        theme: PreviewTheme,
        zoom: Double
    ) -> AttributedString
}
```

缓存 key：

```text
inline content digest
+ preview theme ID
+ appearance
+ zoom
```

链接使用自定义 attribute 或 URL attribute，但点击前必须再次验证 scheme。

### 10.4 Zoom

不要对整个文档简单使用 `.scaleEffect`，因为它会导致布局尺寸、滚动范围和 hit testing 不一致。

建立：

```swift
struct PreviewMetrics {
    let zoom: Double
    let bodyFont: Font
    let codeFont: Font
    let documentInsets: EdgeInsets
    let blockSpacing: CGFloat
    let headingScales: [CGFloat]
    let diagramMaxHeight: CGFloat
}
```

缩放变化时：

- font size
- spacing
- padding
- table cell insets
- diagram displayed size
- code block metrics

按 zoom 比例重新计算。

---

## 11. Tree-sitter 代码高亮

### 11.1 公共协议

```swift
protocol CodeHighlighting: Sendable {
    func highlight(
        source: String,
        language: CodeLanguage?,
        theme: CodeTheme
    ) async -> AttributedString
}
```

### 11.2 实现

```swift
actor TreeSitterCodeHighlighter: CodeHighlighting {
    private let registry: TreeSitterLanguageRegistry
    private let cache: CodeHighlightCache

    func highlight(
        source: String,
        language: CodeLanguage?,
        theme: CodeTheme
    ) async -> AttributedString
}
```

### 11.3 Language registry

```swift
struct TreeSitterLanguageDefinition: Sendable {
    let language: CodeLanguage
    let grammarVersion: String
    let configuration: LanguageConfiguration
    let aliases: Set<String>
}
```

别名至少包含：

```swift
[
    "sh": .bash,
    "shell": .bash,
    "zsh": .bash,

    "c++": .cpp,
    "cc": .cpp,

    "js": .javascript,
    "jsx": .javascript,

    "ts": .typescript,
    "tsx": .typescript,

    "py": .python,
    "rs": .rust,
    "golang": .go,
    "yml": .yaml
]
```

不进行自动语言检测。缺失或未知语言直接显示 plain monospaced text。

### 11.4 Capture normalization

不同 grammar 的 capture 名不完全一致。先归一化：

```swift
enum SyntaxToken: String, Hashable, Sendable {
    case plain
    case comment
    case documentationComment
    case keyword
    case string
    case number
    case type
    case function
    case method
    case property
    case variable
    case parameter
    case constant
    case attribute
    case tag
    case operatorSymbol
    case punctuation
    case label
    case escape
    case embedded
}
```

归一化时支持前缀降级：

```text
function.method.call
    -> function.method
    -> function
    -> plain
```

同一区间存在多个 capture 时，按以下优先级：

1. 更深的 syntax node
2. 更具体的 capture name
3. query 中更晚的 override
4. 明确的 error capture 不覆盖正常 token

### 11.5 生成 AttributedString

实现要求：

- Tree-sitter/NSRange 使用 UTF-16。
- 不得直接把 byte range 当成 Swift String range。
- 先创建完整 plain `AttributedString`。
- 将 capture range 转换成 `AttributedString.Index`。
- 应用 foreground、weight、italic 等属性。
- 保留所有原始字符和换行。
- parse/query 失败时返回 plain text，不抛到 UI。

### 11.6 Code theme

```swift
struct CodeTheme: Identifiable, Hashable, Sendable {
    let id: String
    let background: PlatformColor
    let foreground: PlatformColor
    let selection: PlatformColor
    let styles: [SyntaxToken: SyntaxStyle]
}
```

首批主题：

- DiagramDown Light
- DiagramDown Dark
- GitHub Light
- GitHub Dark
- Paper Light
- Paper Dark

主题不要依赖某个 grammar 的原始 capture 名。

### 11.7 Cache

cache key：

```text
source SHA-256
+ language
+ grammar version
+ highlight query version
+ code theme ID
+ highlighter schema version
```

建议：

- 32 MB 内存 LRU
- 暂不需要磁盘 cache
- memory pressure 时可清空
- 相同代码块在多文件中可共享结果

### 11.8 限制

建议默认：

- `<= 500 KB`：完整高亮
- `500 KB–2 MB`：允许高亮，但在后台执行并显示 plain fallback
- `> 2 MB`：默认不高亮，显示 plain text 和“highlighting skipped”辅助提示
- 单次 parse 可设软超时，但不能强制终止 C parser；通过 task cancellation 避免应用过期结果

### 11.9 CodeBlockView

```swift
struct CodeBlockView: View {
    let blockID: PreviewBlockID
    let source: String
    let language: CodeLanguage?

    @State private var content: AttributedString

    var body: some View {
        ScrollView(.horizontal) {
            Text(content)
                .font(.system(size: metrics.codeFontSize, design: .monospaced))
                .textSelection(.enabled)
                .padding(metrics.codeInsets)
        }
        .background(codeTheme.background)
        .task(id: requestID) {
            content = await highlighter.highlight(
                source: source,
                language: language,
                theme: codeTheme
            )
        }
    }
}
```

首次显示立即使用 plain text，Tree-sitter 完成后无动画替换颜色，避免闪烁和布局跳动。

---

## 12. Diagram render abstraction

### 12.1 Model

```swift
enum DiagramKind: String, Sendable {
    case mermaid
    case d2
}
```

```swift
struct DiagramRenderRequest: Hashable, Sendable {
    let blockID: PreviewBlockID
    let revision: UInt64
    let kind: DiagramKind
    let source: String
    let configuration: DiagramConfiguration
}
```

```swift
struct DiagramRenderResult: Sendable {
    let blockID: PreviewBlockID
    let revision: UInt64
    let sanitizedSVG: String
    let intrinsicSize: CGSize
    let cacheKey: String
}
```

### 12.2 Coordinator

```swift
actor DiagramRenderCoordinator {
    func render(
        _ request: DiagramRenderRequest
    ) async throws -> DiagramRenderResult
}
```

职责：

- route Mermaid/D2
- memory/disk cache
- cancellation
- revision validation
- SVG sanitation
- size validation
- error normalization
- metrics/diagnostics without storing source

### 12.3 通用 cache

将现有 D2 cache 泛化为：

```text
DiagramCache
├── Memory LRU: 32 MB
└── Disk LRU: 256 MB
```

cache key：

```text
diagram kind
+ source hash
+ renderer version
+ configuration
+ appearance/theme
+ sanitizer schema version
```

迁移现有 D2 cache 时：

- 可继续读取旧 D2 entries，或
- 明确 bump cache namespace，使旧 entries 自动淘汰

不要因为 cache migration 阻塞功能迁移。

---

## 13. Mermaid 迁移

### 13.1 设计原则

Mermaid 不能由 `swift-markdown` 或 SwiftUI 自动生成图形。目标不是重写 Mermaid，而是将它隔离为“源码到 SVG”的服务。

```text
Mermaid source
    ↓
MermaidRenderService actor
    ↓
hidden persistent WKWebView
    ↓
Mermaid.js
    ↓
SVG string + intrinsic size
    ↓
Swift SVGSanitizer
    ↓
NativeSVGView
```

### 13.2 Hidden WebView

```swift
@MainActor
final class MermaidWebViewHost: NSObject {
    private let webView: WKWebView

    func loadRuntime() async throws
    func render(_ request: MermaidRuntimeRequest) async throws
        -> MermaidRuntimeResult
}
```

要求：

- 应用级单例或明确生命周期的共享实例
- 永远不加入可见 view hierarchy
- 使用 `.nonPersistent()` website data store
- 不注册不需要的 message handler
- 只加载 bundle 中的本地资源
- CSP：
  - `default-src 'none'`
  - `script-src 'self'`
  - `style-src 'self' 'unsafe-inline'`
  - `img-src data:`
  - `connect-src 'none'`
  - `object-src 'none'`
  - `base-uri 'none'`
  - `form-action 'none'`
- Mermaid：
  - `startOnLoad: false`
  - `securityLevel: "strict"`
  - `htmlLabels: false`
- 参数通过 `callAsyncJavaScript(arguments:)` 传递
- 禁止把 source 拼接进 JavaScript 字符串
- 请求串行执行，避免 Mermaid global state 互相覆盖
- WebContent process terminate 后自动 reload runtime
- runtime readiness 必须有显式状态机
- 不允许任何网络访问

### 13.3 Runtime API

`Resources/MermaidRenderer/renderer.js`：

```javascript
window.mermaidRuntime = Object.freeze({
  render(source, requestID, theme, appearance) {
    // configure, render, sanitize basic output, return serialized SVG and size
  }
});
```

返回：

```javascript
{
  requestID,
  svg,
  width,
  height
}
```

不要在 JS 中保存 Markdown 文档，只处理单个 Mermaid source。

### 13.4 Cancellation

Mermaid.js 的当前 render 未必能被真正中断，因此采用：

- actor 队列
- revision/requestID
- Swift task cancellation
- 过期结果丢弃
- 新 revision 不等待旧结果写入 UI
- service 可继续完成旧 render，但不得污染 cache 或 view state，除非 cache key 仍有效

### 13.5 Mermaid theme

保持现有设置：

- default
- neutral
- forest
- dark
- base

cache key 必须包含：

- light/dark effective appearance
- Mermaid theme
- Mermaid runtime version

---

## 14. D2 迁移

D2 已经是原生服务，不重写 renderer。

### 14.1 保留

- `D2RenderService`
- direct executable invocation
- no shell
- timeout
- cancellation
- source/size limits
- memory/disk cache behavior
- D2 settings
- helper signing and release validation

### 14.2 修改

旧链路：

```text
preview.js -> WKScriptMessageHandler -> D2RenderService -> JS DOM
```

新链路：

```text
DiagramBlockView
    -> DiagramRenderCoordinator
    -> D2RenderService
    -> sanitized SVG
    -> NativeSVGView
```

移除：

- `"d2"` script message handler
- `applyD2Result`
- `applyD2Error`
- JS-side D2 cache
- JS-side D2 SVG sanitizer
- DOM placeholder lifecycle

### 14.3 Cache

优先复用 `DiagramCache`。如果重构风险过大，可以先让 `D2RenderService` 保持现有 cache，待功能稳定后再合并。

---

## 15. SVG sanitation

所有 Mermaid 和 D2 SVG 在进入原生 renderer 或导出前必须经过 Swift 层 sanitizer。

### 15.1 输入限制

- 最大 SVG 字节数：8 MB
- 最大 width/height/viewBox：20,000
- XML depth 限制
- element count 限制
- attribute count/length 限制
- 禁止 DTD
- 禁止 external entity

### 15.2 禁止元素

至少移除或拒绝：

```text
script
foreignObject
iframe
object
embed
audio
video
canvas
```

### 15.3 禁止属性

- 所有 `on*` event handler
- 外部可执行 URL
- `javascript:`
- 非允许的 `data:` 类型
- CSS 中非 fragment/data-image 的 `url(...)`

### 15.4 Link policy

SVG `<a href>` 只允许：

- `http:`
- `https:`
- `mailto:`
- `#fragment`

外部链接由应用点击策略处理，SVG renderer 不得自行导航。

### 15.5 输出

```swift
struct SVGDocument: Hashable, Sendable {
    let sanitizedXML: String
    let intrinsicSize: CGSize
    let digest: String
}
```

导出使用 sanitized XML，而不是未验证原始 SVG。

---

## 16. Native SVG rendering

### 16.1 抽象

```swift
protocol SVGRendering: Sendable {
    associatedtype Body: View

    @ViewBuilder
    func makeView(document: SVGDocument) -> Body
}
```

实际 SwiftUI 中可以使用 type erasure：

```swift
protocol SVGRendererBackend: Sendable {
    @MainActor
    func makeView(document: SVGDocument) -> AnyView
}
```

### 16.2 首选实现

`SVGViewRenderer` 使用 `exyte/SVGView`。

```swift
struct NativeSVGView: View {
    let document: SVGDocument

    var body: some View {
        SVGView(data: Data(document.sanitizedXML.utf8))
            .aspectRatio(
                document.intrinsicSize.width / document.intrinsicSize.height,
                contentMode: .fit
            )
    }
}
```

按实际 `SVGView` API 调整构造方式。

### 16.3 兼容性门槛

在切换默认管线前，建立 Mermaid/D2 SVG fixture suite，至少覆盖：

#### Mermaid

- flowchart
- sequence
- class
- state
- ER
- gantt
- pie
- mindmap
- timeline
- architecture
- subgraph
- edge labels
- light/dark themes

#### D2

- dagre
- elk
- sketch
- nested containers
- icons/images if supported
- multiple themes
- labels
- arrows
- large diagrams

每个 fixture 比较：

- 无 parse failure
- 无缺失文字
- marker/arrow 正确
- transform 正确
- viewBox 正确
- light/dark 可读
- focused viewer 与 inline view 一致

### 16.4 Fallback

若 `SVGView` 无法正确显示某些 SVG：

1. 保留 `SVGRendererBackend` 抽象。
2. 为失败结果记录匿名 capability code，不记录 source。
3. 开发期允许使用隐藏 renderer 生成 raster fallback。
4. 可见预览仍不得嵌入 WKWebView。
5. raster fallback 必须明确标记，不能影响 SVG 导出。
6. 如果通用 SVG 兼容率不足，不要删除旧预览；先修复或替换 backend。

最终目标是常用 Mermaid/D2 fixture 全部使用 native vector backend。

---

## 17. DiagramBlockView

```swift
struct DiagramBlockView: View {
    let block: PreviewBlock
    let configuration: DiagramConfiguration

    @State private var state: DiagramBlockState

    var body: some View {
        Group {
            switch state {
            case .idle, .rendering:
                DiagramPendingView(previous: state.previousDocument)

            case .rendered(let document):
                NativeSVGView(document: document)

            case .failed(let error):
                DiagramErrorView(error: error, source: block.source)
            }
        }
        .overlay(alignment: .topTrailing) {
            DiagramActions(...)
        }
        .task(id: requestID) {
            await render()
        }
    }
}
```

行为要求：

- source 正在修改时保留上一版成功 SVG，叠加轻量 rendering 状态。
- 新结果到达时不闪白。
- 失败时显示 inline error 和可展开 source。
- 支持 Open Preview。
- 支持 Export SVG。
- 点击非按钮区域可定位源码。
- focused viewer 使用同一 `SVGDocument`，不得重新渲染。
- focused viewer 支持 fit、25%–400%、键盘和 pinch zoom。

---

## 18. 双向滚动同步

### 18.1 Geometry reporting

每个顶级 block 上报：

```swift
struct PreviewBlockGeometry: Equatable {
    let blockID: PreviewBlockID
    let sourceRange: PreviewSourceRange
    let minY: CGFloat
    let maxY: CGFloat
}
```

使用 `PreferenceKey` 收集可见 block geometry。

### 18.2 Editor -> Preview

输入：

```text
editor source line
editor document progress
generation
```

算法：

1. 找到包含 source line 的 block。
2. 若不存在，找到前后最近 block。
3. 在 block source range 中计算 line fraction。
4. 在 block `minY...maxY` 中插值。
5. 若 layout 尚未生成，使用 document progress fallback。
6. 使用 `ScrollViewReader` 或底层 `NSScrollView` 动画滚动。
7. 记录 generation，避免回环。

### 18.3 Preview -> Editor

算法：

1. 找到 viewport top 附近的两个 block。
2. 根据 top 在两个 block 之间的位置插值 source line。
3. 若只有一个 block，使用 block 内部比例近似。
4. 输出：
   - source line
   - progress
   - usesProgressFallback
5. 节流到每 frame 最多一次。
6. 用户主动滚动时发送；程序滚动期间 suppress。

### 18.4 Click -> Source

- block root 有 source range。
- inline link/button 不触发 source selection。
- 点击普通区域跳转到 block `startLine`。
- 表格 cell 和列表 item 可使用更精确的 child source range。

### 18.5 状态恢复

继续使用现有 per-file `ScrollSyncState` 概念：

- editor line/progress
- preview line/progress
- generation
- layout readiness

不要把 SwiftUI geometry 持久化；只持久化 source line/progress。

---

## 19. 主题迁移

### 19.1 PreviewTheme

```swift
struct PreviewTheme: Identifiable, Hashable, Sendable {
    let id: String
    let colors: PreviewColors
    let typography: PreviewTypography
    let spacing: PreviewSpacing
    let codeTheme: CodeTheme
}
```

### 19.2 CSS -> Swift

将当前 CSS 中的视觉规则迁移到：

- fonts
- sizes
- weights
- foreground/background
- heading spacing
- paragraph spacing
- blockquote border/insets
- table border/cell padding
- code block background
- inline code style
- link style
- divider style
- image corner radius
- diagram container style

保留：

- DiagramDown
- GitHub
- Paper

不要尝试逐行翻译 CSS；先通过 screenshot fixtures 捕获当前视觉基线，再在 SwiftUI 中实现等价视觉。

### 19.3 Appearance

`PreviewThemeResolver` 输入：

- selected appearance
- system appearance
- markdown theme
- zoom

输出 effective theme。

Mermaid theme 和 D2 theme 继续独立配置。

---

## 20. PDF 导出

当前 WKWebView PDF 导出必须迁移。

### 20.1 Export snapshot

```swift
struct PreviewExportSnapshot: Sendable {
    let document: PreviewDocument
    let resolvedCodeBlocks: [PreviewBlockID: AttributedString]
    let resolvedDiagrams: [PreviewBlockID: SVGDocument]
    let theme: PreviewTheme
    let metadata: ExportMetadata
}
```

创建 snapshot 前：

1. 等待当前 Markdown parse 完成。
2. 等待所有代码块高亮，或明确使用 plain fallback。
3. 等待 Mermaid/D2 渲染。
4. 若存在未完成 diagram，显示可理解错误，不导出半成品。
5. 固化 theme 和 appearance。
6. 关闭 focused diagram viewer。

### 20.2 Print view

建立：

```swift
struct NativePrintablePreviewView: View
```

要求：

- 使用普通 `VStack`，不能使用 `LazyVStack`
- 固定打印宽度
- 隐藏交互按钮
- 链接按主题显示
- 代码块允许换行或按现有打印策略缩放
- diagram 保持 aspect ratio
- 避免横向 scroll container
- 使用 print-specific metrics
- 支持分页时避免标题单独留在页尾
- 尽量避免图表被横向裁切

### 20.3 AppKit pipeline

```text
PreviewExportSnapshot
    ↓
NSHostingView(rootView: NativePrintablePreviewView)
    ↓
layoutSubtreeIfNeeded
    ↓
NSPrintOperation
    ↓
PDF file URL
```

使用 `NSPrintInfo` 配置：

- page size
- margins
- horizontal pagination
- vertical pagination
- save disposition
- output URL

不要使用单页 `dataWithPDF(inside:)` 作为最终分页方案。

### 20.4 Export tests

- 1 page plain document
- multi-page document
- long code block
- table across pages
- Mermaid
- D2
- mixed diagrams
- light/dark export policy
- non-ASCII/CJK
- hyperlinks
- no clipped last line
- no blank trailing page

迁移期允许旧 PDF export 作为 debug fallback，但最终验收前必须切到原生 pipeline。

---

## 21. SVG 导出

新实现不再从 DOM 查询 `<svg>`。

```text
DiagramBlockState.rendered(SVGDocument)
    ↓
NSSavePanel
    ↓
sanitizedXML.data(using: .utf8)
    ↓
atomic write
```

要求：

- 保留现有安全文件名生成逻辑。
- 继续验证 block kind、line suffix 和 base name。
- 导出 sanitized SVG。
- 支持 Mermaid 和 D2。
- 不因 native display backend 降级为 raster 而丢失 SVG export。

---

## 22. Feature flags

```swift
enum PreviewFeatureFlags {
    static var nativePreviewEnabled: Bool
    static var nativeSVGEnabled: Bool
    static var nativePDFExportEnabled: Bool
}
```

规则：

- Release 构建最终不暴露用户可见切换。
- 迁移期 Debug/测试可以使用 launch argument：
  - `-DiagramDownNativePreview YES`
  - `-DiagramDownNativeSVG YES`
  - `-DiagramDownNativePDF YES`
- 旧、新管线不能同时监听同一份滚动状态并互相写入。
- 每个窗口只能激活一个 preview implementation。
- 记录匿名性能 metrics 时区分 pipeline，但不得记录文档内容、路径或名称。

---

## 23. 文件迁移表

| 当前文件 | 操作 |
|---|---|
| `Mark/MarkdownPreviewView.swift` | 先改为 facade，根据 flag 选择 old/new；最终仅保留 native |
| `Mark/Resources/Preview/preview.html` | 最终删除 |
| `Mark/Resources/Preview/preview.css` | 迁移到 Swift theme 后删除 |
| `Mark/Resources/Preview/preview.js` | 最终删除 |
| `Mark/Resources/Preview/markdown-it.min.js` | 最终删除 |
| `Mark/Resources/Preview/highlight.min.js` | Tree-sitter 完成后删除 |
| `Mark/Resources/Preview/mermaid.min.js` | 移到 `Resources/MermaidRenderer/` |
| `Mark/D2RenderService.swift` | 保留并适配直接调用 |
| `Mark/ScrollSyncState.swift` | 保留数据模型，替换 Web bridge |
| `Mark/PreviewSettingsView.swift` | 保留，绑定新 theme/config |
| `Mark/PreviewCommands.swift` | PDF/SVG/zoom 调用迁移到 native services |
| `Tests/PreviewRuntimeTests.mjs` | Mermaid runtime tests 保留一部分；Markdown/scroll/export 测试迁移到 Swift |
| `Scripts/test.sh` | 加入 grammar、native preview、SVG/PDF tests |
| release validation | 增加 SwiftPM licenses、grammar architectures 和资源校验 |

---

## 24. 分阶段实施

## Phase 0：基线与 fixtures

### 工作

- 为旧管线记录：
  - startup preview time
  - first render
  - edit-to-preview latency
  - total memory footprint
  - PDF output
- 创建固定文档 fixtures：
  - `all-markdown.md`
  - `all-code-languages.md`
  - `mermaid-suite.md`
  - `d2-suite.md`
  - `large-document.md`
  - `security.md`
  - `cjk.md`
- 保存旧主题 screenshot baseline。
- 补充当前功能列表测试。

### 完成标准

- 可以量化新旧差异。
- 所有必须保留的功能都有 fixture 或测试。

---

## Phase 1：依赖与模型

### 工作

- 添加 `swift-markdown`
- 添加 `swift-tree-sitter`
- 添加第一批 grammars
- 添加 `SVGView`
- 创建 `PreviewDocument`、block、inline、range、ID 模型
- 创建 feature flags
- 保证旧 preview 默认行为不变

### 完成标准

- App 构建通过。
- release/package validation 识别新增依赖。
- 旧功能无回归。

---

## Phase 2：Markdown parser

### 工作

- 实现 `MarkdownParserService`
- 实现 `MarkdownPreviewVisitor`
- 实现 source range
- 实现 stable ID reconciliation
- 添加 parser snapshot tests
- 特殊处理 Mermaid/D2 fences
- 实现 link/image policy model

### 完成标准

- fixtures 能稳定生成 `PreviewDocument`
- 重复 parse 相同文档产生相同 IDs
- 在文档顶部插入一行后，大部分未变化 block 保持 ID
- source range 与原文行号一致
- raw HTML 不执行

---

## Phase 3：基础原生 View

### 工作

- 实现 heading、paragraph、inline、quote、list、task list、table、code plain view、image、divider
- 实现主题模型
- 实现 zoom metrics
- 实现 native preview facade
- 暂时对 Mermaid/D2 显示 placeholder
- 加入 snapshot tests

### 完成标准

- `all-markdown.md` 功能可用
- 文本选择、复制、链接和图片策略正确
- 三个主题可切换
- 50%–200% zoom 可用
- 可见 view hierarchy 中无 WKWebView

---

## Phase 4：Tree-sitter

### 工作

- 实现 language registry
- 实现 alias mapping
- 实现 capture normalization
- 实现 `TreeSitterCodeHighlighter`
- 实现 cache
- 实现 code block async fallback
- 加入语言 golden tests
- 加入大代码块测试

### 完成标准

- 所有第一批语言有正确高亮
- 未知语言显示 plain text
- 不加载 JavaScriptCore
- 不加载 highlight.js/Prism
- edit revision 变化不会应用旧高亮
- code block layout 在高亮前后不跳动

---

## Phase 5：D2 原生接入

### 工作

- 实现 `DiagramRenderCoordinator`
- 直接调用 `D2RenderService`
- 实现 Swift `SVGSanitizer`
- 实现 `SVGDocument`
- 实现 `NativeSVGView`
- 实现 diagram pending/previous/error state
- 实现 focused viewer 和 SVG export

### 完成标准

- D2 不经过 JS bridge
- D2 fixture suite 全部可显示
- D2 settings 生效
- cache 命中正确
- 旧 SVG export 行为保持

---

## Phase 6：Mermaid 隔离服务

### 工作

- 拆出 `Resources/MermaidRenderer`
- 创建最小 `renderer.html/js`
- 实现 `MermaidWebViewHost`
- 实现 `MermaidRenderService`
- 实现 request/revision/cancellation
- 接入 `DiagramRenderCoordinator`
- 加入 Mermaid runtime tests
- 加入 SVG compatibility tests

### 完成标准

- Mermaid 在原生 preview 中显示
- 可见 preview 中没有 WKWebView
- Mermaid renderer 无网络权限
- Mermaid errors inline 显示
- light/dark theme 正确
- focused viewer 和 SVG export 正确
- WebContent process terminate 后可恢复

---

## Phase 7：滚动同步与交互

### 工作

- 实现 block geometry preference
- 实现 editor -> preview
- 实现 preview -> editor
- 实现 click -> source
- 实现 suppress/generation
- 接入 per-file restoration
- 接入 pinch/keyboard zoom

### 完成标准

- 普通段落、长代码、表格、图表附近同步稳定
- 程序滚动不产生反馈循环
- tab 切换恢复各自位置
- 点击图表和代码区域可定位正确 source line
- 点击链接和按钮不错误跳转源码

---

## Phase 8：原生 PDF

### 工作

- 实现 export snapshot
- 实现 printable view
- 实现 `NSPrintOperation`
- 处理多页、代码、表格、SVG
- 加入 PDF tests
- 切换 `PreviewCommands`

### 完成标准

- 全文分页 PDF 与当前功能等价或更好
- 所有图表已完成时才导出
- CJK 字体正常
- 无裁切、空白尾页或交互控件
- 导出失败有明确错误

---

## Phase 9：性能、安全和兼容性

### 工作

- benchmark 新旧 pipeline
- Instruments 检查主线程和总内存
- 测试 20 KB、200 KB、2 MB 文档
- 测试 500 KB、2 MB code block
- fuzz malformed Markdown/SVG
- 测试恶意 links、raw HTML、SVG event attributes
- 测试 workspace path traversal 和 symlink
- 测试 Mermaid/D2 超时和过期 result
- 测试 memory pressure cache eviction

### 完成标准

- 无主线程 Markdown/Tree-sitter parse
- 无旧 revision 污染
- 安全 fixture 全部通过
- 普通文档整体性能不低于旧 pipeline
- 常见编辑场景主观无闪烁
- 内存和 package-size 结果被记录在文档中

---

## Phase 10：删除旧管线

### 前置条件

以下全部满足后才能执行：

- Markdown 功能 parity
- Tree-sitter parity
- Mermaid/D2 parity
- scroll sync parity
- themes/zoom parity
- SVG/PDF export parity
- test suite green
- performance gate green
- release validation green

### 删除

- Markdown Web preview implementation
- markdown-it
- highlight.js
- preview DOM code
- D2 WebKit bridge
- JS scroll sync
- JS code highlighting
- 旧 PDF export path
- 旧 DOM SVG export path

### 保留

```text
Resources/MermaidRenderer/
├── renderer.html
├── renderer.js
└── mermaid.min.js
```

以及仅供 Mermaid 的隐藏 `WKWebView`。

---

## 25. 测试计划

### 25.1 Parser unit tests

- heading levels
- inline emphasis nesting
- links/images
- quotes
- ordered start value
- nested lists
- task list
- tables and alignment
- code fence info string
- Mermaid/D2 detection
- raw HTML behavior
- Unicode source ranges
- CRLF/LF
- empty document
- malformed Markdown
- stable IDs

### 25.2 Highlighter tests

每种语言至少：

- keywords
- strings
- comments
- numbers
- types/functions
- malformed/incomplete code
- Unicode identifiers
- empty code
- huge code
- aliases
- unknown language
- theme mapping
- UTF-16 ranges

Golden test不要依赖具体颜色值，可先比较 normalized token ranges，再单独测试主题映射。

### 25.3 SVG tests

- sanitizer allowlist
- blocked elements
- event attributes
- URL policies
- malformed XML
- oversized dimensions
- SVGView compatibility
- export roundtrip

### 25.4 Diagram tests

- cache key
- revision cancellation
- stale result rejection
- previous SVG retention
- error state
- theme change
- D2 config change
- Mermaid runtime reload
- SVG export

### 25.5 SwiftUI snapshot tests

- three themes
- light/dark
- zoom levels
- headings/lists/tables/code
- Mermaid/D2
- errors
- CJK
- narrow/wide windows

### 25.6 Integration tests

- edit Markdown and preview update
- rapid typing
- switch tabs during render
- close tab during render
- restore workspace
- click-to-source
- bidirectional scroll
- PDF export
- SVG export
- no network access
- WebContent termination recovery

### 25.7 Release tests

- arm64 grammar binaries
- D2 helper signing
- package licenses
- no unintended dynamic libraries
- sandbox entitlements unchanged
- Gatekeeper validation
- packaged app contains Mermaid runtime
- packaged app no longer contains markdown-it/highlight.js

---

## 26. 性能基线和验收指标

先测旧实现，再以相对指标验收。

### 26.1 场景

| 场景 | 文档 |
|---|---|
| Small | 20 KB，普通 Markdown |
| Medium | 200 KB，混合 Markdown/代码 |
| Large | 2 MB，长文档 |
| Code-heavy | 50 个代码块 |
| Diagram-heavy | 20 Mermaid + 20 D2 |
| Rapid edits | 10 次/秒输入 |
| Tab switching | 10 个打开文件 |

### 26.2 必须满足

- parse/highlight/diagram source processing 不在主线程。
- 普通文档首次可见内容不等待 Mermaid runtime。
- 新 revision 不应用旧 revision 结果。
- 对没有 Mermaid 的文档，不启动 Mermaid runtime，或延迟到第一个 Mermaid block 出现。
- 代码和 diagram cache 命中不重复执行 parser/renderer。
- `LazyVStack` 不造成点击定位和 PDF 内容缺失。
- 普通 Markdown 编辑延迟不差于旧实现超过 10%。
- 无持续增长的 AST、AttributedString、SVG 或 WebKit request 泄漏。

### 26.3 观察目标

这些是优化目标，不是第一版硬门槛：

- 普通文档总内存下降 20% 或更多
- 首次预览更快
- Medium 文档 parse/model p95 小于 100 ms
- 已缓存 code block 恢复接近即时
- 非 Mermaid 文档不产生 WebContent process
- grammar 增加的 release 包体在可接受范围内

如实际结果与目标不同，记录原因和 profile，而不是通过隐藏功能退化来满足数字。

---

## 27. 安全要求

### Markdown

- raw HTML 不执行
- link scheme allowlist
- remote images 默认关闭
- local images 限于 workspace
- 文件大小限制
- 无任意 file URL 访问

### Mermaid

- local assets only
- strict CSP
- `connect-src 'none'`
- non-persistent store
- argument-based JS calls
- strict security level
- no HTML labels
- output size limit
- stale results rejected

### D2

- fixed executable URL
- no shell
- bounded arguments
- timeout
- cancellation
- temporary file cleanup
- sandbox inheritance
- helper signature validation

### SVG

- sanitize before display/export
- no scripts/events/foreignObject
- no external resources
- URL allowlist
- XML entity protection
- size/depth/count limits

### Diagnostics

不得记录：

- Markdown source
- code source
- Mermaid/D2 source
- file names
- full paths
- rendered SVG content

允许记录：

- renderer kind
- anonymous error category
- duration bucket
- byte-size bucket
- cache hit/miss
- grammar ID
- app/runtime version

---

## 28. Codex 实施规则

1. 每个 phase 独立提交，避免一次性重写。
2. 在新功能达到 parity 前不得删除旧实现。
3. 每个 phase 都必须：
   - build
   - unit tests
   - integration tests
   - `Scripts/test.sh`
4. 公共 protocol 和 model 优先于具体 View。
5. 不要把 parser、highlighter 或 renderer 直接实例化在 SwiftUI `body`。
6. 不要在多个 View 中各自创建 Mermaid WebView。
7. 不要通过字符串拼接执行 JavaScript。
8. 不要自动语言检测。
9. 不要为了快速迁移引入 HighlightSwift、Highlightr、Prism 或 markdown-it。
10. 不要将整个 Markdown 文档交给 Mermaid runtime。
11. 不要使用 `AnyView` 作为所有 block 的默认结构；仅在 SVG backend 抽象等必要边界使用。
12. 不要在打印 View 使用 `LazyVStack`。
13. 不要在 source range 和 Tree-sitter range 中混用 UTF-8 byte offset 与 UTF-16 `NSRange`。
14. 所有 async result 应携带 revision/request ID。
15. 所有 cache key 应包含 renderer/parser/theme 版本。
16. 所有 migration deviation 必须写入 `docs/native-preview-migration-notes.md`。

---

## 29. 建议提交序列

```text
1.  test(preview): add native migration fixtures and baselines
2.  build(preview): add swift-markdown and preview feature flags
3.  feat(preview): add PreviewDocument model
4.  feat(preview): parse Markdown into PreviewDocument
5.  feat(preview): reconcile stable preview block identities
6.  feat(preview): add native SwiftUI block rendering
7.  feat(preview): add native themes and zoom metrics
8.  build(highlight): add SwiftTreeSitter and initial grammars
9.  feat(highlight): add Tree-sitter code highlighting
10. feat(svg): add SVG sanitation and native SVG backend
11. refactor(d2): render D2 directly into native preview
12. feat(mermaid): add isolated Mermaid render service
13. feat(diagrams): add native diagram viewer and SVG export
14. feat(scroll): add native bidirectional scroll synchronization
15. feat(export): add native paginated PDF export
16. test(preview): add parity, security, and performance suites
17. perf(preview): optimize caches, layout, and cancellation
18. refactor(preview): make native preview default
19. cleanup(preview): remove markdown-it Web preview runtime
20. docs(preview): update architecture and release documentation
```

---

## 30. 最终验收清单

### 架构

- [ ] Markdown 使用 `swift-markdown`
- [ ] AST 转为 `PreviewDocument`
- [ ] 可见预览完全 SwiftUI 原生
- [ ] 代码高亮使用 Tree-sitter
- [ ] D2 直接调用原生服务
- [ ] Mermaid 仅通过隐藏服务生成 SVG
- [ ] SVG 在原生 View 中显示
- [ ] PDF 使用原生打印管线

### 功能

- [ ] Markdown 常用语法完整
- [ ] GFM 表格、删除线、任务列表
- [ ] 代码高亮
- [ ] Mermaid
- [ ] D2
- [ ] themes
- [ ] light/dark/system
- [ ] zoom
- [ ] scroll sync
- [ ] click-to-source
- [ ] diagram viewer
- [ ] SVG export
- [ ] PDF export
- [ ] tab state restoration

### 安全

- [ ] raw HTML 不执行
- [ ] links allowlist
- [ ] local resource containment
- [ ] Mermaid 无网络
- [ ] D2 不通过 shell
- [ ] SVG sanitation
- [ ] diagnostics 不含文档内容

### 性能

- [ ] parser 不在主线程
- [ ] highlighter 不在主线程
- [ ] diagram render 不阻塞 UI
- [ ] stale result rejection
- [ ] block-level stable IDs
- [ ] code cache
- [ ] diagram memory/disk cache
- [ ] large-document benchmark
- [ ] no reproducible memory leak

### 清理

- [ ] 删除 markdown-it
- [ ] 删除 highlight.js
- [ ] 删除可见 preview HTML/JS/CSS
- [ ] 删除 D2 Web bridge
- [ ] 删除 JS scroll sync
- [ ] 删除旧 PDF/SVG DOM export
- [ ] Mermaid runtime 移入独立资源目录
- [ ] 更新 licenses
- [ ] 更新 architecture docs
- [ ] 更新 release validation

---

## 31. Definition of Done

本迁移仅在以下条件同时满足时完成：

1. DiagramDown 默认使用原生 SwiftUI Markdown preview。
2. 用户可见 view hierarchy 中不存在 `WKWebView`。
3. 普通 Markdown 和代码高亮不运行 JavaScript。
4. Mermaid 与 D2 的常用 fixture 均能正确显示。
5. 旧版本的主题、缩放、同步、SVG 导出和 PDF 导出能力均被保留。
6. 旧 Markdown Web preview 代码和资源已删除。
7. Mermaid 的隐藏 renderer 是唯一保留的 WebKit 使用点。
8. 全部自动测试、release validation 和 security tests 通过。
9. 性能和内存结果已与旧实现对比并记录。
10. `README`、架构文档、打包文档和许可证清单已更新。
