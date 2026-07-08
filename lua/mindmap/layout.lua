local M = {}

--- Helper to traverse all nodes in the tree.
local function traverse(node, cb)
  if not node then return end
  cb(node)
  for _, child in ipairs(node.children) do
    traverse(child, cb)
  end
end

--- Pass 1: Computes box_width and subtree_width bottom-up.
--- @param node table The current Node
--- @param sibling_gap number Horizontal gap between sibling subtrees
local function calculate_subtree_widths(node, sibling_gap)
  node.box_width = math.max(6, #node.text + 4)

  if #node.children == 0 then
    node.subtree_width = node.box_width
  else
    local children_width = 0
    for _, child in ipairs(node.children) do
      calculate_subtree_widths(child, sibling_gap)
      children_width = children_width + child.subtree_width
    end
    children_width = children_width + (#node.children - 1) * sibling_gap
    node.subtree_width = math.max(node.box_width, children_width)
  end
end

--- Pass 2: Assigns rows and columns top-down, centering parent boxes.
--- @param node table The current Node
--- @param row number Row index (1-based)
--- @param center_col number Centered column index
--- @param row_gap number Row step between tiers
--- @param sibling_gap number Horizontal gap between sibling subtrees
local function assign_positions(node, row, center_col, row_gap, sibling_gap)
  node.row = row
  node.center_col = center_col
  node.col = center_col - math.floor(node.box_width / 2)

  if #node.children > 0 then
    local children_width = 0
    for _, child in ipairs(node.children) do
      children_width = children_width + child.subtree_width
    end
    children_width = children_width + (#node.children - 1) * sibling_gap

    local start_col = center_col - math.floor(children_width / 2)
    local current_left = start_col

    for _, child in ipairs(node.children) do
      local child_center = current_left + math.floor(child.subtree_width / 2)
      assign_positions(child, row + row_gap, child_center, row_gap, sibling_gap)
      current_left = current_left + child.subtree_width + sibling_gap
    end
  end
end

--- Pass 3: Adjusts all positions to ensure they are within buffer bounds (col >= margin, row >= 1).
--- Returns the bounds of the rendered grid (max_row, max_col).
--- @param root table The root Node
--- @param margin number Left margin offset
--- @return number max_row
--- @return number max_col
local function shift_positions(root, margin)
  local min_col = 999999
  local min_row = 999999
  local max_col = 1
  local max_row = 1

  traverse(root, function(n)
    if n.col < min_col then
      min_col = n.col
    end
    if n.row < min_row then
      min_row = n.row
    end
  end)

  local col_offset = 0
  if min_col < margin then
    col_offset = margin - min_col
  end

  local row_offset = 0
  if min_row < 1 then
    row_offset = 1 - min_row
  end

  traverse(root, function(n)
    n.col = n.col + col_offset
    n.center_col = n.center_col + col_offset
    n.row = n.row + row_offset

    local right_edge = n.col + n.box_width - 1
    if right_edge > max_col then
      max_col = right_edge
    end

    local bottom_edge = n.row + 2
    if bottom_edge > max_row then
      max_row = bottom_edge
    end
  end)

  return max_row, max_col
end

--- Computes subtree heights bottom-up for horizontal layout.
local function calculate_subtree_heights(node, sibling_gap)
  node.box_width = math.max(6, #node.text + 4)
  node.box_height = 3

  if #node.children == 0 then
    node.subtree_height = node.box_height
  else
    local children_height = 0
    for _, child in ipairs(node.children) do
      calculate_subtree_heights(child, sibling_gap)
      children_height = children_height + child.subtree_height
    end
    children_height = children_height + (#node.children - 1) * sibling_gap
    node.subtree_height = math.max(node.box_height, children_height)
  end
end

--- Assigns horizontal positions top-down.
local function assign_horizontal_positions(node, col, center_row, col_gap, sibling_gap)
  node.row = center_row - 1
  node.col = col
  node.center_col = col + math.floor(node.box_width / 2)

  if #node.children > 0 then
    local children_height = 0
    for _, child in ipairs(node.children) do
      children_height = children_height + child.subtree_height
    end
    children_height = children_height + (#node.children - 1) * sibling_gap

    local start_row = center_row - math.floor(children_height / 2)
    local current_top = start_row

    for _, child in ipairs(node.children) do
      local child_center_row = current_top + math.floor(child.subtree_height / 2)
      local next_col = col + node.box_width + col_gap
      assign_horizontal_positions(child, next_col, child_center_row, col_gap, sibling_gap)
      current_top = current_top + child.subtree_height + sibling_gap
    end
  end
end

--- Computes the full visual layout of the tree.
--- Mutates nodes by adding: row, col, center_col, box_width, subtree_width/height.
--- @param root table The root Node
--- @param opts table Layout options (layout, row_gap, col_gap, sibling_gap, margin)
--- @return number max_row Total rows required
--- @return number max_col Total columns required
function M.compute_layout(root, opts)
  if not root then return 0, 0 end

  opts = opts or {}
  local layout = opts.layout or "vertical"
  local margin = opts.margin or 2
  local sibling_gap = opts.sibling_gap or 2

  if layout == "horizontal" then
    local col_gap = opts.col_gap or 4
    calculate_subtree_heights(root, sibling_gap)
    assign_horizontal_positions(root, margin, 1, col_gap, sibling_gap)
  else
    local row_gap = opts.row_gap or 4
    calculate_subtree_widths(root, sibling_gap)
    assign_positions(root, 1, 40, row_gap, sibling_gap)
  end

  local max_row, max_col = shift_positions(root, margin)

  return max_row, max_col
end

return M
