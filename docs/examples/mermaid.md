# Mermaid preview smoke test

This document exercises DiagramDown's local Mermaid rendering (`mmdr` by
default, or `mmdc` from Settings). Each section uses a common diagram type.

## Flowchart

```mermaid
flowchart LR
    EDIT[Edit Markdown] --> PARSE[Parse fenced block]
    PARSE --> RENDER[Render SVG]
    RENDER --> PREVIEW[Live preview]
```

## Sequence diagram

```mermaid
sequenceDiagram
    participant U as User
    participant D as DiagramDown
    participant M as Mermaid
    U->>D: Edit diagram source
    D->>M: Render locally
    M-->>D: SVG
    D-->>U: Updated preview
```

## Class diagram

```mermaid
classDiagram
    class Document {
        +String path
        +String text
        +save()
        +reload()
    }
    class Preview {
        +render(source)
    }
    class Renderer {
        <<interface>>
        +render(source) SVG
    }
    Document --> Preview : drives
    Preview --> Renderer : uses
    Renderer <|.. MmdrRenderer
    Renderer <|.. MmdcRenderer
```

## State diagram

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Rendering: source changed
    Rendering --> Ready: success
    Rendering --> Failed: error
    Failed --> Rendering: retry
    Ready --> Rendering: source changed
    Ready --> [*]
```

## Entity-relationship diagram

```mermaid
erDiagram
    WORKSPACE ||--o{ DOCUMENT : contains
    DOCUMENT ||--o{ DIAGRAM_BLOCK : embeds
    DOCUMENT {
        string path
        string text
    }
    DIAGRAM_BLOCK {
        string kind
        string source
    }
    TOOL ||--o{ DIAGRAM_BLOCK : renders
    TOOL {
        string name
        string version
    }
```

## Gantt chart

```mermaid
gantt
    title DiagramDown release prep
    dateFormat  YYYY-MM-DD
    section Docs
    Expand examples           :a1, 2026-07-27, 1d
    Update changelog          :a2, after a1, 1d
    section App
    SVG transparency fix      :b1, 2026-07-27, 1d
    QA preview smoke tests    :b2, after b1, 2d
```

## Pie chart

```mermaid
pie showData
    title Preview time by renderer
    "mmdr SVG" : 55
    "mmdc PNG" : 25
    "D2 SVG" : 20
```

## User journey

```mermaid
journey
    title Authoring a diagram in DiagramDown
    section Write
      Open workspace: 5: Author
      Edit Mermaid fence: 4: Author
    section Preview
      Watch live render: 5: Author
      Export SVG: 3: Author
```

## Git graph

```mermaid
gitGraph
    commit id: "init"
    commit id: "editor"
    branch feature
    checkout feature
    commit id: "mmdr"
    commit id: "examples"
    checkout main
    merge feature id: "0.26.0"
```

## Mind map

```mermaid
mindmap
    root((DiagramDown))
        Editor
            Markdown
            Line highlight
        Preview
            Mermaid
            D2
            Images
        Tools
            mmdr
            mmdc
            d2
```

## Timeline

```mermaid
timeline
    title DiagramDown milestones
    2026-07 : Native Markdown preview
           : Local mmdc and D2 CLIs
    2026-07 : Workspace tree workflows
           : Image insertion
    2026-07 : mmdr SVG renderer option
           : Transparent diagram canvases
```

## Quadrant chart

```mermaid
quadrantChart
    title Diagram tooling trade-offs
    x-axis Low fidelity --> High fidelity
    y-axis Slow --> Fast
    quadrant-1 Fast and rich
    quadrant-2 Fast sketch
    quadrant-3 Slow sketch
    quadrant-4 Slow and rich
    mmdr: [0.55, 0.85]
    mmdc: [0.80, 0.35]
    d2: [0.75, 0.70]
```

## XY chart

```mermaid
xychart-beta
    title "Preview latency (ms)"
    x-axis [flowchart, sequence, class, er]
    y-axis "ms" 0 --> 120
    bar [18, 24, 30, 22]
    line [18, 24, 30, 22]
```

## C4 context

```mermaid
C4Context
    title DiagramDown system context
    Person(author, "Author", "Writes Markdown and diagrams")
    System(dd, "DiagramDown", "Offline Markdown workspace")
    System_Ext(cli, "Local CLIs", "mmdr / mmdc / d2")
    Rel(author, dd, "Edits and previews")
    Rel(dd, cli, "Renders fenced diagrams")
```

## Sankey

```mermaid
sankey-beta
Markdown, Preview, 40
Markdown, Export, 10
Preview, Mermaid, 25
Preview, D2, 15
Mermaid, mmdr, 18
Mermaid, mmdc, 7
```

## Block diagram

```mermaid
block-beta
    columns 3
    workspace["Workspace"]:3
    tree["File tree"] editor["Editor"] preview["Preview"]
    workspace --> tree
    workspace --> editor
    workspace --> preview
```

## Requirement diagram

```mermaid
requirementDiagram
    requirement live_preview {
        id: 1
        text: Diagrams update from local CLIs
        risk: low
        verifymethod: test
    }
    element DiagramDown {
        type: application
    }
    DiagramDown - satisfies -> live_preview
```

## Unicode labels

```mermaid
flowchart TD
    A[中文内容] --> B[Offline rendering]
    B --> C[Done]
```
