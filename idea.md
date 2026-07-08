# PRD: mindmap.nvim

## 1. Summary

A Neovim plugin for creating and navigating mindmaps without leaving the editor. Plain-text outline is the source of truth; the plugin renders it two ways — a fast-to-type outline view and a spatial tree view — toggled with a single keybind. No external GUI, no image rendering, terminal-native.

## 2. Problem

Mindmapping tools force a context switch out of the editor (Freeplane, Xmind, web apps). For quick structural thinking — planning a feature, breaking down an RFC, sketching a roadmap — that switch has too much friction. Neovim has no equivalent of an outliner-with-a-visual-projection.

## 3. Goals

- Edit mindmaps as fast as writing a normal indented list
- See the tree spatially without leaving the terminal
- Store maps as plain diffable text, not a binary/JSON blob
- Zero external dependencies (no graphviz, no image protocol requirement)

## 4. Non-goals

- Radial/free-form spatial layout (v1 is strict top-down tree only)
- Real-time multi-cursor collaboration
- Rich node content (images, embedded code blocks) — v1 nodes are single-line text
- Cross-platform terminal graphics (kitty protocol, ueberzug) — explicitly avoided to keep this working everywhere Neovim runs, including over SSH/tmux

## 5. Data model

Maps are stored as `.mm` files: plain indented markdown-style outline.

```
- Gherkio v2
  - Transform block
    - Array proj
      - dot path
      - wildcard
    - Filters
  - Report UI
    - Try-it
      - CORS fix
    - Token mask
```

This is the single source of truth. Both UI modes below are pure projections of this text — parsed into a tree, never a separate data store. Editing in outline mode edits this text directly; editing in map mode mutates the same in-memory tree and writes back to it.

## 6. UI expectations

Two modes, one buffer, one keybind (`gm`) to toggle. Statusline always shows current mode (`-- MAP --` / `-- OUTLINE --`) and node position (`node 4/9`), consistent with how Neovim already signals mode.

### 6.1 Outline mode
Standard indented text buffer. This is where fast entry happens — `o`/`O` to add nodes, `Tab`/`Shift-Tab` to indent/outdent, normal Neovim motions and macros all work unmodified since it's just text.

### 6.2 Map mode
Spatial, top-down tree layout. Each node renders as a bordered box (floating window or extmark-drawn rect), color-coded by depth using the user's existing colorscheme highlight groups — not hardcoded colors. Connectors between parent and children are drawn as clean right-angle elbow lines (`│ ─ ╭ ╰`), never diagonals — diagonal lines in a monospace grid have no room to breathe and were the main source of visual cramping in early concepts. Generous vertical spacing between depth tiers and horizontal spacing between siblings is mandatory; layout must never let sibling boxes touch or crowd.

Reference mockup (approved concept):

- Root node centered at top, single accent color
- Each depth tier in its own horizontal band with consistent vertical gap
- Sibling nodes spaced by their subtree width, not fixed pixel/column spacing, so dense subtrees don't crowd their neighbors
- Node box: rounded/single border, 1-2 lines of text, color = depth (not category, to avoid needing a legend)
- Selected node has a distinct border weight/color, matching Neovim's own cursorline convention

**What it actually looks like on screen** (buffer content, map mode, cursor on "Try-it"):

```
                              ╭──────────────╮
                              │  Gherkio v2  │
                              ╰──────┬───────╯
                    ╭─────────────────┴─────────────────╮
           ╭────────┴────────╮                 ╭─────────┴────────╮
           │ Transform block  │                 │     Report UI     │
           ╰────────┬────────╯                 ╰─────────┬─────────╯
             ╭───────┴───────╮                  ╭─────────┴─────────╮
      ╭──────┴─────╮   ╭─────┴────╮      ┏━━━━━━┷━━━┓        ╭──────┴──────╮
      │ Array proj │   │ Filters  │      ┃  Try-it   ┃        │ Token mask  │
      ╰──────┬─────╯   ╰──────────╯      ┗━━━━━━━━━━━┛        ╰─────────────╯
        ╭─────┴─────╮
   ╭────┴───╮   ╭────┴─────╮
   │dot path│   │ wildcard │
   ╰────────╯   ╰──────────╯

-- MAP --  roadmap.mm                                          node 4/9
```

Notes on the mockup:
- Thin single-border box (`╭─╮`) = normal node. Thick border (`┏━┓`) = node under cursor — same visual weight as Neovim's `cursorline`, no color dependency needed to spot it.
- Connectors are strictly elbows (`│ ─ ╭ ╰ ┬ ┴`), never diagonal — this is the fix for the "cramped" feedback from the earlier concept.
- Depth is the only color channel (root → tier 1 → tier 2 → tier 3), each mapped to a highlight group so it re-themes automatically with the user's colorscheme instead of hardcoded hex.
- Statusline mirrors Neovim's own mode indicator convention (`-- MAP --` / `-- OUTLINE --`) plus a node counter, so mode state is never ambiguous.

Equivalent outline-mode view of the same data (toggled via `gm`):

```
- Gherkio v2
  - Transform block
    - Array proj
      - dot path
      - wildcard
    - Filters
  - Report UI
    - Try-it
    - Token mask

-- OUTLINE --  roadmap.mm                                      node 4/9
```

### 6.3 Keybinds (v1)

| Key | Action |
|---|---|
| `o` | Add child node |
| `O` | Add sibling node |
| `Tab` / `Shift-Tab` | Indent / outdent node |
| `hjkl` | Move between parent / child / siblings (map mode) or normal line motion (outline mode) |
| `gm` | Toggle outline ↔ map mode |
| `dd` | Delete node (and subtree, with confirm) |

## 7. Rendering architecture

- **Layout pass**: pure Lua, no Neovim API calls. Tree-width algorithm — each node's width = sum of children's subtree widths; position = centered over its children. Outputs row/col coordinates only.
- **Node rendering**: `nvim_open_win()` floating windows per node (v1 preferred — enables in-place node editing), each with `border = "rounded"`, `winhighlight` mapped to a depth-based highlight group table that adapts to the active colorscheme.
- **Connector rendering**: `nvim_buf_set_extmark()` with `virt_lines`/`virt_text` in the underlying scratch buffer, drawing elbow segments at coordinates computed by the layout pass. This is the one piece floating windows can't handle natively.
- **Mode toggle**: two renderers reading the same parsed tree — outline renderer writes indented text to a normal buffer; map renderer opens/positions floating windows and draws extmarks. No dual data model.

## 8. Open questions

- Floating windows per node vs. single scratch buffer with drawn box characters — floating windows cost more API calls but give real editable node content; scratch buffer is cheaper and simpler to reason about for layout. Needs a v1 decision before implementation starts.
- Large maps (50+ nodes): does the layout pass need horizontal scroll/pan, or a collapse/fold mechanism per subtree?
- Undo semantics when toggling modes mid-edit.

## 9. Milestones

1. Outline mode only (parser + text buffer editing) — validates data model
2. Static map rendering (layout + floating windows + connectors, read-only)
3. Map mode editing (add/delete/reparent nodes spatially)
4. Mode toggle + statusline integration
5. Colorscheme-adaptive highlighting, polish