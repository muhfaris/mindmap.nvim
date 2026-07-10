local M = {}

local ns_id = vim.api.nvim_create_namespace("mindmap")

-- Default highlight groups definition
function M.setup_highlights()
  local highlights = {
    MindmapDepth0 = { link = "Title" },
    MindmapDepth1 = { link = "String" },
    MindmapDepth2 = { link = "Identifier" },
    MindmapDepth3 = { link = "Constant" },
    MindmapDepth4 = { link = "Special" },
    MindmapSelected = { link = "CursorLine" },
    MindmapConnector = { link = "Comment" },
  }

  for group, definition in pairs(highlights) do
    vim.api.nvim_set_hl(0, group, definition)
  end
end

-- Helper to draw characters in grid
local function draw_char(grid, row, col, char)
  if not grid[row] then
    grid[row] = {}
  end
  grid[row][col] = char
end

-- Helper to draw a string in grid
local function draw_string(grid, row, start_col, str)
  if not grid[row] then
    grid[row] = {}
  end
  -- Split the string into UTF-8 characters
  local chars = {}
  for char in str:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    table.insert(chars, char)
  end
  for idx, char in ipairs(chars) do
    grid[row][start_col + idx - 1] = char
  end
end

-- Draw a single node box
local function draw_node(grid, node, is_selected, layout)
  local row = node.row
  local col = node.col
  local w = node.box_width

  -- Border chars
  local tl, tr, bl, br, h, v, p_conn, c_conn
  if is_selected then
    tl, tr, bl, br, h, v = "┏", "┓", "┗", "┛", "━", "┃"
    if layout == "horizontal" or layout == "split" then
      p_conn, c_conn = "┫", "┣"
    else
      p_conn, c_conn = "┻", "┳"
    end
  else
    tl, tr, bl, br, h, v = "╭", "╮", "╰", "╯", "─", "│"
    if layout == "horizontal" or layout == "split" then
      p_conn, c_conn = "┤", "├"
    else
      p_conn, c_conn = "┴", "┬"
    end
  end

  local draw_left_conn = false
  local draw_right_conn = false

  if layout == "horizontal" then
    if node.parent then
      draw_left_conn = true
    end
    if #node.children > 0 and not node.collapsed then
      draw_right_conn = true
    end
  elseif layout == "split" then
    if not node.parent then
      -- Root node
      local has_left = false
      local has_right = false
      for _, child in ipairs(node.children) do
        if child.direction == "left" then
          has_left = true
        else
          has_right = true
        end
      end
      if has_left and not node.collapsed then
        draw_left_conn = true
      end
      if has_right and not node.collapsed then
        draw_right_conn = true
      end
    else
      -- Non-root node
      if node.direction == "left" then
        if node.parent then
          draw_right_conn = true
        end
        if #node.children > 0 and not node.collapsed then
          draw_left_conn = true
        end
      else
        if node.parent then
          draw_left_conn = true
        end
        if #node.children > 0 and not node.collapsed then
          draw_right_conn = true
        end
      end
    end
  end

  -- 1. Top border
  draw_char(grid, row, col, tl)
  for c = col + 1, col + w - 2 do
    draw_char(grid, row, c, h)
  end
  draw_char(grid, row, col + w - 1, tr)
  if layout ~= "horizontal" and layout ~= "split" and node.parent then
    draw_char(grid, row, node.center_col, p_conn)
  end

  -- 2. Text line
  draw_char(grid, row + 1, col, draw_left_conn and p_conn or v)
  for c = col + 1, col + w - 2 do
    draw_char(grid, row + 1, c, " ")
  end
  draw_char(grid, row + 1, col + w - 1, draw_right_conn and c_conn or v)

  -- Center the text inside the box
  local display_text = node.text
  if node.collapsed and #node.children > 0 then
    display_text = display_text .. " ⊕"
  end
  local text_len = vim.fn.strdisplaywidth(display_text)
  local inner_width = w - 2
  local padding_left = math.floor((inner_width - text_len) / 2)
  draw_string(grid, row + 1, col + 1 + padding_left, display_text)

  -- 3. Bottom border
  draw_char(grid, row + 2, col, bl)
  for c = col + 1, col + w - 2 do
    draw_char(grid, row + 2, c, h)
  end
  draw_char(grid, row + 2, col + w - 1, br)
  if layout ~= "horizontal" and layout ~= "split" and #node.children > 0 and not node.collapsed then
    draw_char(grid, row + 2, node.center_col, c_conn)
  end
end

-- Draw right-angle elbow connectors for vertical layout
local function draw_vertical_connectors(grid, node)
  if #node.children == 0 then return end

  local conn_row = node.row + 3

  if #node.children == 1 then
    draw_char(grid, conn_row, node.center_col, "│")
  else
    local centers = {}
    for _, child in ipairs(node.children) do
      table.insert(centers, child.center_col)
    end
    table.sort(centers)

    local first = centers[1]
    local last = centers[#centers]

    for c = first, last do
      if c == node.center_col then
        local is_child = false
        for _, child in ipairs(node.children) do
          if child.center_col == c then
            is_child = true
            break
          end
        end
        if is_child then
          draw_char(grid, conn_row, c, "┼")
        else
          draw_char(grid, conn_row, c, "┴")
        end
      else
        local is_child = false
        for _, child in ipairs(node.children) do
          if child.center_col == c then
            is_child = true
            break
          end
        end

        if is_child then
          if c == first then
            draw_char(grid, conn_row, c, "╭")
          elseif c == last then
            draw_char(grid, conn_row, c, "╮")
          else
            draw_char(grid, conn_row, c, "┬")
          end
        else
          draw_char(grid, conn_row, c, "─")
        end
      end
    end
  end
end

-- Draw right-angle connectors for horizontal layout
local function draw_horizontal_connectors(grid, node, children_list)
  local children = children_list or node.children
  if #children == 0 then return end

  local parent_right = node.col + node.box_width - 1
  local parent_center_row = node.row + 1

  if #children == 1 then
    local child = children[1]
    for c = parent_right + 1, child.col - 1 do
      draw_char(grid, parent_center_row, c, "─")
    end
  else
    local centers = {}
    for _, child in ipairs(children) do
      table.insert(centers, child.row + 1)
    end
    table.sort(centers)

    local min_y = centers[1]
    local max_y = centers[#centers]
    local branch_col = parent_right + 2

    -- Vertical line branch
    for r = min_y, max_y do
      draw_char(grid, r, branch_col, "│")
    end

    -- Parent to branch
    for c = parent_right + 1, branch_col - 1 do
      draw_char(grid, parent_center_row, c, "─")
    end

    -- Branch to children
    for _, child in ipairs(children) do
      local child_center_row = child.row + 1
      for c = branch_col + 1, child.col - 1 do
        draw_char(grid, child_center_row, c, "─")
      end
    end

    -- Intersection corners at branch_col
    for _, child in ipairs(children) do
      local y = child.row + 1
      if y == min_y then
        draw_char(grid, y, branch_col, "╭")
      elseif y == max_y then
        draw_char(grid, y, branch_col, "╰")
      else
        draw_char(grid, y, branch_col, "├")
      end
    end

    -- Parent meeting vertical branch
    local is_child_at_parent_y = false
    for _, child in ipairs(children) do
      if child.row + 1 == parent_center_row then
        is_child_at_parent_y = true
        break
      end
    end

    if is_child_at_parent_y then
      if parent_center_row == min_y then
        draw_char(grid, parent_center_row, branch_col, "┬")
      elseif parent_center_row == max_y then
        draw_char(grid, parent_center_row, branch_col, "┴")
      else
        draw_char(grid, parent_center_row, branch_col, "┼")
      end
    else
      draw_char(grid, parent_center_row, branch_col, "┤")
    end
  end
end

-- Draw right-angle connectors for left-growing horizontal layout
local function draw_left_horizontal_connectors(grid, node, children_list)
  local children = children_list or node.children
  if #children == 0 then return end

  local parent_left = node.col
  local parent_center_row = node.row + 1

  if #children == 1 then
    local child = children[1]
    for c = child.col + child.box_width, parent_left - 1 do
      draw_char(grid, parent_center_row, c, "─")
    end
  else
    local centers = {}
    for _, child in ipairs(children) do
      table.insert(centers, child.row + 1)
    end
    table.sort(centers)

    local min_y = centers[1]
    local max_y = centers[#centers]
    local branch_col = parent_left - 2

    -- Vertical line branch
    for r = min_y, max_y do
      draw_char(grid, r, branch_col, "│")
    end

    -- Parent to branch
    for c = branch_col + 1, parent_left - 1 do
      draw_char(grid, parent_center_row, c, "─")
    end

    -- Branch to children
    for _, child in ipairs(children) do
      local child_center_row = child.row + 1
      for c = child.col + child.box_width, branch_col - 1 do
        draw_char(grid, child_center_row, c, "─")
      end
    end

    -- Intersection corners at branch_col
    for _, child in ipairs(children) do
      local y = child.row + 1
      if y == min_y then
        draw_char(grid, y, branch_col, "╮")
      elseif y == max_y then
        draw_char(grid, y, branch_col, "╯")
      else
        draw_char(grid, y, branch_col, "┤")
      end
    end

    -- Parent meeting vertical branch
    local is_child_at_parent_y = false
    for _, child in ipairs(children) do
      if child.row + 1 == parent_center_row then
        is_child_at_parent_y = true
        break
      end
    end

    if is_child_at_parent_y then
      if parent_center_row == min_y then
        draw_char(grid, parent_center_row, branch_col, "┬")
      elseif parent_center_row == max_y then
        draw_char(grid, parent_center_row, branch_col, "┴")
      else
        draw_char(grid, parent_center_row, branch_col, "┼")
      end
    else
      draw_char(grid, parent_center_row, branch_col, "├")
    end
  end
end

-- Convert grid character tables to strings
local function grid_to_lines(grid, max_row, max_col)
  local lines = {}
  local grid_chars = {}

  for r = 1, max_row do
    local row_chars = {}
    local max_c_used = 1
    for c = 1, max_col do
      local char = (grid[r] and grid[r][c]) or " "
      row_chars[c] = char
      if char ~= " " then
        max_c_used = c
      end
    end

    local trimmed = {}
    for c = 1, max_c_used do
      table.insert(trimmed, row_chars[c])
    end

    grid_chars[r] = trimmed
    lines[r] = table.concat(trimmed)
  end

  return lines, grid_chars
end

-- Highlight nodes and connectors based on box cell occupancy
local function apply_highlights(bufnr, root, selected_node_id, grid_chars)
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  local function get_byte_range(row_chars, start_char, end_char)
    local start_byte = 0
    for i = 1, start_char - 1 do
      start_byte = start_byte + #(row_chars[i] or " ")
    end
    local end_byte = start_byte
    for i = start_char, end_char do
      end_byte = end_byte + #(row_chars[i] or " ")
    end
    return start_byte, end_byte
  end

  local box_cells = {}
  local function mark_box_cells(node)
    for r = node.row, node.row + 2 do
      if not box_cells[r] then box_cells[r] = {} end
      for c = node.col, node.col + node.box_width - 1 do
        box_cells[r][c] = true
      end
    end
    if not node.collapsed then
      for _, child in ipairs(node.children) do
        mark_box_cells(child)
      end
    end
  end
  mark_box_cells(root)

  local function traverse_hl(node)
    local is_selected = (node.id == selected_node_id)
    local hl_group = is_selected and "MindmapSelected" or ("MindmapDepth" .. math.min(4, node.depth))

    -- Highlight the 3 lines of the box
    for r = node.row, node.row + 2 do
      local row_chars = grid_chars[r]
      if row_chars then
        local s_byte, e_byte = get_byte_range(row_chars, node.col, node.col + node.box_width - 1)
        vim.api.nvim_buf_add_highlight(bufnr, ns_id, hl_group, r - 1, s_byte, e_byte)
      end
    end

    if not node.collapsed then
      for _, child in ipairs(node.children) do
        traverse_hl(child)
      end
    end
  end
  traverse_hl(root)

  -- Highlight connectors
  for r = 1, #grid_chars do
    local row_chars = grid_chars[r]
    if row_chars then
      local in_connector = false
      local start_c = nil

      for c = 1, #row_chars do
        local char = row_chars[c]
        local is_box = (box_cells[r] and box_cells[r][c])
        local is_non_space = (char and char ~= " " and char ~= "")

        if is_non_space and not is_box then
          if not in_connector then
            in_connector = true
            start_c = c
          end
        else
          if in_connector then
            local s_byte, e_byte = get_byte_range(row_chars, start_c, c - 1)
            vim.api.nvim_buf_add_highlight(bufnr, ns_id, "MindmapConnector", r - 1, s_byte, e_byte)
            in_connector = false
          end
        end
      end

      if in_connector then
        local s_byte, e_byte = get_byte_range(row_chars, start_c, #row_chars)
        vim.api.nvim_buf_add_highlight(bufnr, ns_id, "MindmapConnector", r - 1, s_byte, e_byte)
      end
    end
  end
end

--- Renders the entire tree into the scratch buffer.
--- @param bufnr number The scratch buffer number
--- @param root table The root Node of the tree
--- @param selected_node_id string The ID of the currently selected node
--- @param layout string? Optional layout orientation: "vertical" (default) or "horizontal"
function M.render_map(bufnr, root, selected_node_id, layout)
  layout = layout or "vertical"
  local opts = {
    layout = layout,
    row_gap = 4,
    col_gap = 4,
    sibling_gap = 2,
    margin = 2,
  }

  -- 1. Compute visual coordinates
  local max_row, max_col = require("mindmap.layout").compute_layout(root, opts)

  -- 2. Draw nodes and connectors into the 2D grid
  local grid = {}

  local function traverse_draw(node)
    local is_selected = (node.id == selected_node_id)
    draw_node(grid, node, is_selected, layout)
    if not node.collapsed then
      if layout == "horizontal" or layout == "split" then
        if node.direction == "left" then
          draw_left_horizontal_connectors(grid, node)
        elseif node.direction == "right" then
          draw_horizontal_connectors(grid, node)
        else
          if layout == "split" then
            local left_children = {}
            local right_children = {}
            for _, child in ipairs(node.children) do
              if child.direction == "left" then
                table.insert(left_children, child)
              else
                table.insert(right_children, child)
              end
            end
            if #left_children > 0 then
              draw_left_horizontal_connectors(grid, node, left_children)
            end
            if #right_children > 0 then
              draw_horizontal_connectors(grid, node, right_children)
            end
          else
            draw_horizontal_connectors(grid, node)
          end
        end
      else
        draw_vertical_connectors(grid, node)
      end

      for _, child in ipairs(node.children) do
        traverse_draw(child)
      end
    end
  end

  traverse_draw(root)

  -- 3. Convert grid to lines and grid_chars
  local lines, grid_chars = grid_to_lines(grid, max_row, max_col)

  -- 4. Write lines to the buffer
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })

  -- 5. Apply highlight groups
  apply_highlights(bufnr, root, selected_node_id, grid_chars)
end

return M
