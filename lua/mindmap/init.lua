local M = {}

M.states = {} -- bufnr -> state table

M.config = {
  layout = "vertical",
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  if M.config.layout then
    vim.g.mindmap_layout = M.config.layout
  end
end

local is_snapping = false

--- Recursively updates descendant depth values.
local function update_descendant_depths(node)
  for _, child in ipairs(node.children) do
    child.depth = node.depth + 1
    update_descendant_depths(child)
  end
end

--- Redraws the map in the scratch buffer and snaps the cursor.
function M.redraw(state)
  require("mindmap.render").render_map(state.map_bufnr, state.tree, state.selected_node_id, state.layout)

  local sel = state.node_by_id[state.selected_node_id]
  if sel then
    is_snapping = true
    local win = vim.fn.bufwinid(state.map_bufnr)
    if win ~= -1 then
      vim.api.nvim_win_set_cursor(win, { sel.row + 1, sel.center_col - 1 })
      local cur_win = vim.api.nvim_get_current_win()
      if cur_win == win then
        pcall(vim.cmd, "normal! zz")
      end
    end
    is_snapping = false
  end
end

--- Updates the source outline buffer with the current tree, then redraws the map.
function M.update_tree_and_redraw(state)
  local lines = require("mindmap.parser").serialize_tree(state.tree)
  vim.api.nvim_buf_set_lines(state.src_buf, 0, -1, false, lines)
  M.redraw(state)
end

--- Toggles the layout of the mindmap for the current buffer.
function M.toggle_layout()
  local buf = vim.api.nvim_get_current_buf()
  local state = M.states[buf]

  -- If in map buffer, locate the state based on the map buffer
  if not state then
    for _, st in pairs(M.states) do
      if st.map_bufnr == buf then
        state = st
        break
      end
    end
  end

  if not state then
    vim.notify("No active mindmap state found for this buffer", vim.log.levels.WARN)
    return
  end

  if state.layout == "horizontal" then
    state.layout = "vertical"
  else
    state.layout = "horizontal"
  end

  if state.mode == "map" then
    M.redraw(state)
  end
end

--- Main toggle function (Outline <-> Map).
function M.toggle()
  local src_buf = vim.api.nvim_get_current_buf()
  local state = M.states[src_buf]

  -- If in map buffer, locate the state based on the map buffer
  local is_in_map = false
  for _, st in pairs(M.states) do
    if st.map_bufnr == src_buf then
      state = st
      is_in_map = true
      break
    end
  end

  if not state then
    state = {
      src_buf = src_buf,
      mode = "outline",
      map_bufnr = nil,
      tree = nil,
      selected_node_id = nil,
      node_by_id = {},
      layout = vim.g.mindmap_layout or M.config.layout or "vertical",
    }
    M.states[src_buf] = state
  end

  if state.mode == "outline" and not is_in_map then
    -- Toggle to MAP mode
    local lines = vim.api.nvim_buf_get_lines(state.src_buf, 0, -1, false)
    local tree, node_by_id = require("mindmap.parser").parse_lines(lines)
    if not tree then
      vim.notify("Empty outline, cannot show map", vim.log.levels.WARN)
      return
    end

    state.tree = tree
    state.node_by_id = node_by_id

    -- Find matching selected node based on cursor position in outline
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
    local selected_node = nil
    for _, node in pairs(node_by_id) do
      if node.line_num == cursor_line then
        selected_node = node
        break
      end
    end
    if not selected_node then
      selected_node = tree
    end
    state.selected_node_id = selected_node.id

    -- Setup map scratch buffer
    local map_buf = state.map_bufnr
    if not map_buf or not vim.api.nvim_buf_is_valid(map_buf) then
      map_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(map_buf, "mindmap://map/" .. state.src_buf)
      vim.api.nvim_set_option_value("buftype", "nofile", { buf = map_buf })
      vim.api.nvim_set_option_value("bufhidden", "hide", { buf = map_buf })
      vim.api.nvim_set_option_value("swapfile", false, { buf = map_buf })
      vim.api.nvim_set_option_value("filetype", "mindmap-map", { buf = map_buf })
      state.map_bufnr = map_buf
      M.setup_map_keymaps(map_buf, state.src_buf)
      M.setup_map_autocmds(map_buf, state.src_buf)
    end

    state.mode = "map"

    -- Render the map
    require("mindmap.render").render_map(map_buf, tree, state.selected_node_id, state.layout)

    -- Switch window to map buffer
    vim.api.nvim_win_set_buf(0, map_buf)

    -- Center cursor on selected node
    local sel = node_by_id[state.selected_node_id]
    vim.api.nvim_win_set_cursor(0, { sel.row + 1, sel.center_col - 1 })
  else
    -- Toggle to OUTLINE mode
    if not state.tree then return end

    -- Serialize tree back to lines
    local lines = require("mindmap.parser").serialize_tree(state.tree)
    vim.api.nvim_buf_set_lines(state.src_buf, 0, -1, false, lines)

    state.mode = "outline"

    -- Switch window back to source buffer
    vim.api.nvim_win_set_buf(0, state.src_buf)

    -- Place cursor on matching outline line
    local sel = state.node_by_id[state.selected_node_id]
    if sel and sel.line_num then
      vim.api.nvim_win_set_cursor(0, { math.min(#lines, sel.line_num), 0 })
    end
  end
end

--- Configures the map buffer local keymaps.
function M.setup_map_keymaps(map_buf, src_buf)
  local function map(key, fn, desc)
    vim.keymap.set("n", key, function()
      local state = M.states[src_buf]
      if state then fn(state) end
    end, { buffer = map_buf, silent = true, desc = desc })
  end

  -- Mode switch
  map("gm", function() M.toggle() end, "Switch to outline mode")

  -- Layout Toggle
  map("gl", function() M.toggle_layout() end, "Toggle Layout (vertical <-> horizontal)")

  -- Navigation (adaptive to layout)
  map("k", function(state)
    if state.layout == "horizontal" then
      M.navigate(state, "prev_sibling")
    else
      M.navigate(state, "parent")
    end
  end, "Navigate parent / prev sibling")

  map("j", function(state)
    if state.layout == "horizontal" then
      M.navigate(state, "next_sibling")
    else
      M.navigate(state, "child")
    end
  end, "Navigate child / next sibling")

  map("h", function(state)
    if state.layout == "horizontal" then
      M.navigate(state, "parent")
    else
      M.navigate(state, "prev_sibling")
    end
  end, "Navigate parent / prev sibling")

  map("l", function(state)
    if state.layout == "horizontal" then
      M.navigate(state, "child")
    else
      M.navigate(state, "next_sibling")
    end
  end, "Navigate child / next sibling")

  -- Structural Actions
  map("o", function(state) M.add_child(state) end, "Create child node")
  map("O", function(state) M.add_sibling(state) end, "Create sibling node")
  map("dd", function(state) M.delete_node(state) end, "Delete node and subtree")
  map("<Tab>", function(state) M.indent_node(state) end, "Indent node")
  map("<S-Tab>", function(state) M.outdent_node(state) end, "Outdent node")

  -- Editing Actions
  map("i", function(state) M.edit_node(state) end, "Edit node text")
  map("a", function(state) M.edit_node(state) end, "Edit node text")
  map("cc", function(state) M.edit_node(state) end, "Edit node text")
  map("<CR>", function(state) M.edit_node(state) end, "Edit node text")
end

--- Configures cursor tracking in map mode.
function M.setup_map_autocmds(map_buf, src_buf)
  local group = vim.api.nvim_create_augroup("MindmapMap_" .. map_buf, { clear = true })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = map_buf,
    callback = function()
      local state = M.states[src_buf]
      if state then
        M.on_cursor_moved(state)
      end
    end,
  })
end

--- Navigation logic.
function M.navigate(state, dir)
  local sel = state.node_by_id[state.selected_node_id]
  if not sel then return end

  local target = nil

  if dir == "parent" then
    target = sel.parent
  elseif dir == "child" then
    if #sel.children > 0 then
      target = sel.children[1]
    end
  elseif dir == "prev_sibling" then
    if sel.parent then
      for idx, child in ipairs(sel.parent.children) do
        if child.id == sel.id then
          if idx > 1 then
            target = sel.parent.children[idx - 1]
          end
          break
        end
      end
    end
  elseif dir == "next_sibling" then
    if sel.parent then
      for idx, child in ipairs(sel.parent.children) do
        if child.id == sel.id then
          if idx < #sel.parent.children then
            target = sel.parent.children[idx + 1]
          end
          break
        end
      end
    end
  end

  if target then
    state.selected_node_id = target.id
    M.redraw(state)
  end
end

--- Edit existing node text via cursor-positioned float.
function M.edit_node(state)
  local node = state.node_by_id[state.selected_node_id]
  if not node then return end
  if node.is_virtual then
    vim.notify("Cannot edit virtual workspace root", vim.log.levels.WARN)
    return
  end

  local text_len = vim.fn.strdisplaywidth(node.text)
  local inner_width = node.box_width - 2
  local padding_left = math.floor((inner_width - text_len) / 2)
  local text_start_col = node.col + 1 + padding_left

  -- Snap cursor to center first to guarantee the cursor is on the correct line/col
  vim.api.nvim_win_set_cursor(0, { node.row + 1, node.center_col - 1 })

  local edit_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(edit_buf, 0, -1, false, { node.text })

  local win_row = (node.row + 1) - vim.fn.line("w0")
  local win_col = (text_start_col - 1) - vim.fn.winsaveview().leftcol

  local win_width = math.max(15, text_len + 5)
  local edit_win = vim.api.nvim_open_win(edit_buf, true, {
    relative = "win",
    row = win_row,
    col = win_col,
    width = win_width,
    height = 1,
    style = "minimal",
    border = "none",
  })

  vim.api.nvim_set_option_value("winhl", "Normal:NormalFloat", { win = edit_win })
  vim.api.nvim_set_option_value("wrap", false, { win = edit_win })

  -- Dynamically adjust window width as the user types to prevent text hiding
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = edit_buf,
    callback = function()
      if not vim.api.nvim_win_is_valid(edit_win) then return end
      local lines = vim.api.nvim_buf_get_lines(edit_buf, 0, 1, false)
      local current_text = lines[1] or ""
      local current_len = vim.fn.strdisplaywidth(current_text)
      local new_width = math.max(15, current_len + 5)
      vim.api.nvim_win_set_config(edit_win, { width = new_width })
    end,
  })

  vim.cmd("startinsert!")

  local saved = false
  local function save_changes()
    if saved then return end
    saved = true

    local lines = vim.api.nvim_buf_get_lines(edit_buf, 0, 1, false)
    local new_text = lines[1] or ""

    pcall(vim.api.nvim_win_close, edit_win, true)
    pcall(vim.api.nvim_buf_delete, edit_buf, { force = true })

    node.text = new_text
    M.update_tree_and_redraw(state)
  end

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = edit_buf,
    once = true,
    callback = save_changes,
  })

  vim.keymap.set({ "n", "i" }, "<CR>", save_changes, { buffer = edit_buf, silent = true })
  vim.keymap.set({ "n", "i" }, "<Esc>", save_changes, { buffer = edit_buf, silent = true })
end

--- Add child node.
function M.add_child(state)
  local sel = state.node_by_id[state.selected_node_id]
  if not sel then return end

  local new_node = require("mindmap.parser").Node.new("New Node", sel.depth + 1, nil)
  new_node.parent = sel
  table.insert(sel.children, new_node)
  state.node_by_id[new_node.id] = new_node

  state.selected_node_id = new_node.id
  M.update_tree_and_redraw(state)
  M.edit_node(state)
end

--- Add sibling node.
function M.add_sibling(state)
  local sel = state.node_by_id[state.selected_node_id]
  if not sel then return end

  if not sel.parent then
    vim.notify("Cannot add sibling to root node", vim.log.levels.WARN)
    return
  end

  local parent = sel.parent
  local new_node = require("mindmap.parser").Node.new("New Node", sel.depth, nil)
  new_node.parent = parent
  state.node_by_id[new_node.id] = new_node

  local idx = nil
  for i, child in ipairs(parent.children) do
    if child.id == sel.id then
      idx = i
      break
    end
  end

  if idx then
    table.insert(parent.children, idx + 1, new_node)
  else
    table.insert(parent.children, new_node)
  end

  state.selected_node_id = new_node.id
  M.update_tree_and_redraw(state)
  M.edit_node(state)
end

--- Delete selected node and its subtree.
function M.delete_node(state)
  local sel = state.node_by_id[state.selected_node_id]
  if not sel then return end

  if not sel.parent then
    local confirm = vim.fn.confirm("Delete root node and entire tree?", "&Yes\n&No", 2)
    if confirm == 1 then
      vim.api.nvim_win_set_buf(0, state.src_buf)
      vim.api.nvim_buf_set_lines(state.src_buf, 0, -1, false, {})
      state.mode = "outline"
      state.tree = nil
      state.node_by_id = {}
      if state.map_bufnr and vim.api.nvim_buf_is_valid(state.map_bufnr) then
        vim.api.nvim_buf_delete(state.map_bufnr, { force = true })
        state.map_bufnr = nil
      end
    end
    return
  end

  if #sel.children > 0 then
    local confirm = vim.fn.confirm("Delete node and its " .. #sel.children .. " children?", "&Yes\n&No", 2)
    if confirm ~= 1 then return end
  end

  local parent = sel.parent
  for idx, child in ipairs(parent.children) do
    if child.id == sel.id then
      table.remove(parent.children, idx)
      break
    end
  end

  local function remove_map(n)
    state.node_by_id[n.id] = nil
    for _, child in ipairs(n.children) do
      remove_map(child)
    end
  end
  remove_map(sel)

  state.selected_node_id = parent.id
  M.update_tree_and_redraw(state)
end

--- Indent node (make child of previous sibling).
function M.indent_node(state)
  local sel = state.node_by_id[state.selected_node_id]
  if not sel or not sel.parent then return end

  local parent = sel.parent
  local idx = nil
  for i, child in ipairs(parent.children) do
    if child.id == sel.id then
      idx = i
      break
    end
  end

  if idx and idx > 1 then
    local prev = parent.children[idx - 1]
    table.remove(parent.children, idx)

    sel.parent = prev
    sel.depth = prev.depth + 1
    update_descendant_depths(sel)

    table.insert(prev.children, sel)
    M.update_tree_and_redraw(state)
  end
end

--- Outdent node (make sibling of parent).
function M.outdent_node(state)
  local sel = state.node_by_id[state.selected_node_id]
  if not sel or not sel.parent or not sel.parent.parent then return end

  local parent = sel.parent
  local grandparent = parent.parent

  local idx = nil
  for i, child in ipairs(parent.children) do
    if child.id == sel.id then
      idx = i
      break
    end
  end

  if idx then
    table.remove(parent.children, idx)

    sel.parent = grandparent
    sel.depth = grandparent.depth + 1
    update_descendant_depths(sel)

    local p_idx = nil
    for i, child in ipairs(grandparent.children) do
      if child.id == parent.id then
        p_idx = i
        break
      end
    end

    if p_idx then
      table.insert(grandparent.children, p_idx + 1, sel)
    else
      table.insert(grandparent.children, sel)
    end

    M.update_tree_and_redraw(state)
  end
end

--- Snap tracking cursor handler.
function M.on_cursor_moved(state)
  if is_snapping then return end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local r, c = cursor[1], cursor[2] + 1

  local found = nil
  for _, node in pairs(state.node_by_id) do
    if r >= node.row and r <= node.row + 2 and c >= node.col and c <= node.col + node.box_width - 1 then
      found = node
      break
    end
  end

  if found then
    if found.id ~= state.selected_node_id then
      state.selected_node_id = found.id
      is_snapping = true
      M.redraw(state)
      is_snapping = false
    end
  else
    local sel = state.node_by_id[state.selected_node_id]
    if sel then
      is_snapping = true
      vim.api.nvim_win_set_cursor(0, { sel.row + 1, sel.center_col - 1 })
      is_snapping = false
    end
  end
end

-- Initialize colorscheme-adaptive highlight groups on load
require("mindmap.render").setup_highlights()

return M
