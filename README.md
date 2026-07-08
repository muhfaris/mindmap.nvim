# mindmap.nvim

A lightweight, terminal-native, spatial mindmapping plugin for Neovim written in 100% Lua. It converts hierarchical text outlines (`.mm` files) into a spatial 2D tree diagram inside a read-only scratch buffer with interactive cursor navigation and live editing.

---

## Features

- **Bidirectional Outline <-> Map Toggling**: Press `gm` in any `.mm` outline file to project it as a visual tree. Syncs cursor position perfectly between modes.
- **Vertical & Horizontal (L-to-R) layouts**: Choose between a vertical tree layout (ideal for deep, narrow hierarchies) or a horizontal left-to-right layout (ideal for wide, shallow trees). Toggle dynamically with `gl`.
- **Adaptive Snapped Navigation**: Snapped directional keys (`h`, `j`, `k`, `l`) adapt on-the-fly to your active layout.
- **Single Scratch Buffer Rendering**: High performance, native scroll/pan support, and pixel-perfect connector lines using box-drawing characters.
- **Adaptive Theme Highlights**: Node depths link dynamically to your editor's colorscheme highlight groups (`Title`, `String`, `Identifier`, etc.).
- **Snapped Cursor Navigation**: Cursor automatically snaps to the center of node boxes, locking movement to the tree structure.
- **In-Place Text Editing**: Press `<CR>` or `i` over a node to open a borderless single-line float. Saving auto-updates the layout and outline file.
- **Structural Tree Operations**: Create children/siblings, indent/outdent, and delete nodes/subtrees directly in map mode.

---

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "muhfaris/mindmap.nvim",
  config = function()
    require("mindmap").setup({
      -- Default options
      layout = "vertical", -- or "horizontal"
    })
  end,
}
```

---

## Usage

### 1. The Data File
Create a text file with the `.mm` extension. Write a standard markdown-style list where hierarchy is defined by indentation (spaces or tabs):

```markdown
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

### 2. Enter Map Mode
Press `gm` (or run `:MindmapToggle`) inside the `.mm` buffer. The editor will transition into a spatial 2D mindmap.

### 3. Controls (Map Mode)

| Key | Description |
| :--- | :--- |
| `gm` | Switch back to Outline Mode (returns cursor to the correct line) |
| `gl` | Toggle layout mode dynamically between Vertical and Horizontal |
| `h` | Move to left sibling (Vertical) / Move to parent node (Horizontal) |
| `l` | Move to right sibling (Vertical) / Move to first child node (Horizontal) |
| `k` | Move up to parent node (Vertical) / Move to upper sibling (Horizontal) |
| `j` | Move down to first child (Vertical) / Move to lower sibling (Horizontal) |
| `i` / `a` / `cc` / `<CR>` | Edit selected node text (opens floating input window) |
| `o` | Add child node |
| `O` | Add sibling node |
| `dd` | Delete selected node and its subtree |
| `<Tab>` | Indent (make child of previous sibling) |
| `<S-Tab>` | Outdent (make sibling of parent) |

---

## Customization

You can customize the default layout globally via a global variable or setup configuration:

```lua
-- Set default layout to horizontal globally
vim.g.mindmap_layout = "horizontal"
```

The plugin creates default highlight groups that link directly to standard Neovim highlight groups. You can customize them in your colorscheme or init configuration:

```lua
-- Examples:
vim.api.nvim_set_hl(0, "MindmapDepth0", { fg = "#ff007f", bold = true }) -- Root node
vim.api.nvim_set_hl(0, "MindmapDepth1", { fg = "#00f0ff" })             -- Depth 1 nodes
vim.api.nvim_set_hl(0, "MindmapSelected", { bg = "#2e3440" })           -- Cursor snapped node
vim.api.nvim_set_hl(0, "MindmapConnector", { fg = "#4c566a" })          -- Right-angle line connections
```

Default linkages:
- `MindmapDepth0` -> `Title`
- `MindmapDepth1` -> `String`
- `MindmapDepth2` -> `Identifier`
- `MindmapDepth3` -> `Constant`
- `MindmapDepth4` -> `Special`
- `MindmapSelected` -> `CursorLine`
- `MindmapConnector` -> `Comment`
