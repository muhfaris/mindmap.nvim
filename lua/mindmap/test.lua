-- Headless tests for mindmap.nvim
-- Run with: nvim --headless -c "set rtp+=." -c "luafile lua/mindmap/test.lua" -c "qa!"

package.loaded["mindmap"] = nil
package.loaded["mindmap.parser"] = nil
package.loaded["mindmap.layout"] = nil
package.loaded["mindmap.render"] = nil

local parser = require("mindmap.parser")
local layout = require("mindmap.layout")

local test_lines = {
  "- Root Node",
  "  - Child 1",
  "    - Grandchild 1",
  "    - Grandchild 2",
  "  - Child 2",
}

print("----------------------------------------")
print("Running parser tests...")
local root, node_by_id = parser.parse_lines(test_lines)

assert(root ~= nil, "Root should not be nil")
assert(root.text == "Root Node", "Root text mismatch: " .. tostring(root.text))
assert(#root.children == 2, "Root should have 2 children, got: " .. #root.children)

local child1 = root.children[1]
assert(child1.text == "Child 1", "Child 1 text mismatch: " .. tostring(child1.text))
assert(#child1.children == 2, "Child 1 should have 2 children, got: " .. #child1.children)

local child2 = root.children[2]
assert(child2.text == "Child 2", "Child 2 text mismatch: " .. tostring(child2.text))
assert(#child2.children == 0, "Child 2 should have 0 children, got: " .. #child2.children)

print("Parser tests passed!")

print("----------------------------------------")
print("Running layout tests...")
local max_row, max_col = layout.compute_layout(root, { row_gap = 4, sibling_gap = 2, margin = 2 })

print("Layout Computed -> Max Row: " .. max_row .. ", Max Col: " .. max_col)
assert(max_row > 0, "Max row should be > 0")
assert(max_col > 0, "Max col should be > 0")

-- Verify coordinates are assigned
traverse_count = 0
local function check_coords(node)
  traverse_count = traverse_count + 1
  assert(node.row ~= nil, "Node row coordinate is nil for: " .. node.text)
  assert(node.col ~= nil, "Node col coordinate is nil for: " .. node.text)
  assert(node.center_col ~= nil, "Node center_col is nil for: " .. node.text)
  print(string.format("Node '%s': row=%d, col=%d, center_col=%d, width=%d",
    node.text, node.row, node.col, node.center_col, node.box_width))
  for _, child in ipairs(node.children) do
    check_coords(child)
  end
end
check_coords(root)
assert(traverse_count == 5, "Should have laid out all 5 nodes, got: " .. traverse_count)

print("Layout tests passed!")

print("----------------------------------------")
print("Running serialization tests...")
local serialized = parser.serialize_tree(root, 2)
for i, line in ipairs(serialized) do
  print(string.format("%d: %s", i, line))
end
assert(#serialized == 5, "Serialized lines count mismatch: " .. #serialized)
assert(serialized[1] == "- Root Node", "Root line mismatch")
assert(serialized[2] == "  - Child 1", "Child 1 line mismatch")
assert(serialized[3] == "    - Grandchild 1", "Grandchild 1 line mismatch")

-- Check line numbers match serialization output
assert(root.line_num == 1, "Root line_num mismatch: " .. tostring(root.line_num))
assert(child1.line_num == 2, "Child 1 line_num mismatch: " .. tostring(child1.line_num))
assert(child1.children[1].line_num == 3, "Grandchild 1 line_num mismatch: " .. tostring(child1.children[1].line_num))

print("Serialization tests passed!")

print("----------------------------------------")
print("Running parser edge-case tests...")

-- Test mixed bullets and empty lines
local mixed_lines = {
  "",
  "* Root",
  "  - Child A",
  "    + Grandchild A1",
  "",
  "  * Child B",
}
local m_root, m_node_by_id = parser.parse_lines(mixed_lines)
assert(m_root ~= nil, "Root should not be nil with mixed bullets")
assert(m_root.text == "Root", "Root text mismatch: " .. tostring(m_root.text))
assert(#m_root.children == 2, "Root should have 2 children, got: " .. #m_root.children)
assert(m_root.children[1].text == "Child A")
assert(m_root.children[1].children[1].text == "Grandchild A1")
assert(m_root.children[2].text == "Child B")

-- Test multiple roots (should group under a virtual root)
local multi_root_lines = {
  "- Root 1",
  "- Root 2",
}
local mr_root, _ = parser.parse_lines(multi_root_lines)
assert(mr_root.is_virtual == true, "Should create a virtual root")
assert(mr_root.text == "Workspace", "Virtual root name should be 'Workspace'")
assert(#mr_root.children == 2, "Virtual root should have 2 children")
assert(mr_root.children[1].text == "Root 1")
assert(mr_root.children[1].depth == 1)
assert(mr_root.children[2].text == "Root 2")
assert(mr_root.children[2].depth == 1)

print("Parser edge-case tests passed!")

print("----------------------------------------")
print("Running anchor/link reference tests...")

local ref_lines = {
  "- Root Node",
  "  - [id:step1] First step",
  "    - Substep 1.1",
  "  - Step 2",
  "    - [link:step1]",
}
local r_root, r_node_by_id = parser.parse_lines(ref_lines)

assert(r_root ~= nil, "Ref root should not be nil")
assert(#r_root.children == 2, "Root should have 2 children")

local step1 = r_root.children[1]
assert(step1.anchor_id == "step1", "step1 should have anchor_id")
assert(step1.text == "First step", "step1 text should be First step")
assert(#step1.children == 1, "step1 should have 1 child")
assert(step1.children[1].text == "Substep 1.1", "step1 child text mismatch")

local step2 = r_root.children[2]
assert(#step2.children == 1, "step2 should have 1 child (the link)")
local link_node = step2.children[1]
assert(link_node.link_id == "step1", "link_node should have link_id")
assert(link_node.text == "First step", "link_node should resolve and clone step1's text")
assert(link_node.is_clone == nil, "link_node itself is not is_clone (it is a link node)")
assert(link_node.origin == step1, "link_node.origin should point to step1")

assert(#link_node.children == 1, "link_node should clone step1's children list")
local cloned_child = link_node.children[1]
assert(cloned_child.text == "Substep 1.1", "cloned child text mismatch")
assert(cloned_child.is_clone == true, "cloned child should have is_clone flag")
assert(cloned_child.origin == step1.children[1], "cloned child origin should point to Substep 1.1")

-- Verify serialization is clean (omits cloned children under link_node)
local r_serialized = parser.serialize_tree(r_root, 2)
assert(#r_serialized == 5, "Serialized lines count mismatch: " .. #r_serialized)
assert(r_serialized[1] == "- Root Node", "Root mismatch")
assert(r_serialized[2] == "  - [id:step1] First step", "Anchor mismatch")
assert(r_serialized[3] == "    - Substep 1.1", "Substep mismatch")
assert(r_serialized[4] == "  - Step 2", "Step 2 mismatch")
assert(r_serialized[5] == "    - [link:step1]", "Link serialization mismatch")

-- Verify circular reference handling
local circular_lines = {
  "- Root Node",
  "  - [id:a] Node A",
  "    - [link:b]",
  "  - [id:b] Node B",
  "    - [link:a]",
}
local c_root, _, c_warnings = parser.parse_lines(circular_lines)
assert(c_root ~= nil, "Circular root should not be nil")
local node_a = c_root.children[1]
local link_b = node_a.children[1]
assert(link_b.text == "Node B", "link_b should resolve to Node B")
local node_b_clone = link_b.children[1]
assert(node_b_clone.text == "Node A", "Node B clone's child should resolve to Node A")
local node_a_clone = node_b_clone.children[1]
assert(node_a_clone.text == "[link:b] (circular reference)", "Circular reference should be detected and marked")
assert(#c_warnings == 1, "Should have exactly 1 warning for circular reference")
assert(c_warnings[1].type == "circular_reference", "Warning type mismatch")
assert(c_warnings[1].id == "b", "Warning id mismatch")

-- Verify broken link handling
local broken_lines = {
  "- Root Node",
  "  - [link:nonexistent]",
}
local b_root, _, b_warnings = parser.parse_lines(broken_lines)
assert(b_root ~= nil, "Broken root should not be nil")
local broken_link = b_root.children[1]
assert(broken_link.text == "[link:nonexistent] (broken link)", "Broken link should be marked")
assert(#b_warnings == 1, "Should have exactly 1 warning for broken link")
assert(b_warnings[1].type == "broken_link", "Warning type mismatch")
assert(b_warnings[1].id == "nonexistent", "Warning id mismatch")

-- Verify duplicate anchor warning
local duplicate_lines = {
  "- Root Node",
  "  - [id:dup] Node 1",
  "  - [id:dup] Node 2",
}
local d_root, _, d_warnings = parser.parse_lines(duplicate_lines)
assert(d_root ~= nil, "Duplicate root should not be nil")
assert(#d_warnings == 1, "Should have exactly 1 warning for duplicate anchor")
assert(d_warnings[1].type == "duplicate_anchor", "Warning type mismatch")
assert(d_warnings[1].id == "dup", "Warning id mismatch")

print("Anchor/link reference tests passed!")

print("----------------------------------------")
print("Running state operations tests...")

package.loaded["mindmap"] = nil
local init = require("mindmap")
print("Loaded mindmap path:", vim.api.nvim_get_runtime_file("lua/mindmap/init.lua", true)[1])
print("init.toggle_collapse:", tostring(init.toggle_collapse))

-- Test setup configuration
init.setup({ layout = "horizontal" })
assert(init.config.layout == "horizontal", "Setup should configure config layout option")
assert(vim.g.mindmap_layout == "horizontal", "Setup should configure global layout variable")
init.setup({ layout = "vertical" })

local mock_lines = {
  "- Root",
  "  - Child 1",
  "  - Child 2",
}
local tree, node_by_id = parser.parse_lines(mock_lines)
local state = {
  src_buf = 999,
  map_bufnr = 888,
  tree = tree,
  selected_node_id = tree.children[2].id, -- Select Child 2
  node_by_id = node_by_id,
}

-- Mock update_tree_and_redraw to inspect serialization
init.update_tree_and_redraw = function(st)
  st.last_serialized = parser.serialize_tree(st.tree)
end

-- Helper to get active references from state since re-parsing creates new nodes
local function get_active_nodes()
  local root = state.tree
  local child1 = root.children[1]
  local child2 = root.children[2]
  if not child2 and child1 then
    child2 = child1.children[1]
  end
  return root, child1, child2
end

-- Test indent_node (Child 2 should become child of Child 1)
local tree, c1, c2 = get_active_nodes()
assert(c2.parent == tree)

init.indent_node(state)
tree, c1, c2 = get_active_nodes()
assert(c2.parent == c1, "Child 2 should now be child of Child 1")
assert(c2.depth == 2, "Child 2 depth should be updated to 2")
assert(#c1.children == 1, "Child 1 should have 1 child")
assert(c1.children[1] == c2)
assert(#tree.children == 1, "Root should now have 1 child")

-- Test outdent_node (Child 2 should become sibling of Child 1 under Root again)
init.outdent_node(state)
tree, c1, c2 = get_active_nodes()
assert(c2.parent == tree, "Child 2 should be reparented to Root")
assert(c2.depth == 1, "Child 2 depth should be 1")
assert(#tree.children == 2, "Root should have 2 children again")

-- Test add_child to Child 1
state.selected_node_id = c1.id
init.edit_node = function() end -- Stub out window float editor

init.add_child(state)
tree, c1, c2 = get_active_nodes()
assert(#c1.children == 1, "Child 1 should have a new child")
local new_child = c1.children[1]
assert(new_child.text == "New Node", "Default text should be 'New Node'")
assert(new_child.depth == 2)
assert(state.selected_node_id == new_child.id, "New child should be selected")

-- Test add_sibling
init.add_sibling(state)
tree, c1, c2 = get_active_nodes()
assert(#c1.children == 2, "Child 1 should now have 2 children")
local sibling = c1.children[2]
assert(sibling.text == "New Node")
assert(sibling.depth == 2)
assert(state.selected_node_id == sibling.id, "New sibling should be selected")

-- Test delete_node
init.delete_node(state)
tree, c1, c2 = get_active_nodes()
assert(#c1.children == 1, "Sibling should be deleted")
assert(state.selected_node_id == c1.id, "Selection should snap back to parent")

-- Test toggle_layout
state.layout = "vertical"
init.states[999] = state
local orig_get_buf = vim.api.nvim_get_current_buf
vim.api.nvim_get_current_buf = function() return 999 end
local orig_redraw = init.redraw
init.redraw = function() end

init.toggle_layout()
assert(state.layout == "horizontal", "Layout should toggle to horizontal")
init.toggle_layout()
assert(state.layout == "split", "Layout should toggle to split")
init.toggle_layout()
assert(state.layout == "vertical", "Layout should toggle back to vertical")

vim.api.nvim_get_current_buf = orig_get_buf
init.redraw = orig_redraw

print("State operations tests passed!")

print("----------------------------------------")
print("Running clone mutation propagation tests...")

local clone_lines = {
  "- Root Node",
  "  - [id:src] Original Source",
  "    - Nested Child",
  "  - Section 2",
  "    - [link:src]",
}
local c_tree, c_node_by_id = parser.parse_lines(clone_lines)
local c_state = {
  src_buf = 999,
  map_bufnr = 888,
  tree = c_tree,
  node_by_id = c_node_by_id,
}

local function get_live_clone_nodes()
  local root = c_state.tree
  local src = root.children[1]
  local sec2 = root.children[2]
  local clone = sec2.children[1]
  return root, src, clone
end

local root, src, clone = get_live_clone_nodes()
assert(clone.origin == src, "Clone origin link mismatch")
assert(#src.children == 1, "Source should start with 1 child")
assert(#clone.children == 1, "Clone should also start with 1 child")

-- 1. Test add_child on the clone
c_state.selected_node_id = clone.id
init.add_child(c_state)

root, src, clone = get_live_clone_nodes()
-- Verify both src and clone now have the new child
assert(#src.children == 2, "Source should have 2 children now")
assert(src.children[2].text == "New Node", "Added child text mismatch under source")
assert(#clone.children == 2, "Clone should have 2 children now (cloned from source)")
assert(clone.children[2].text == "New Node", "Added child text mismatch under clone")

-- 2. Test add_sibling on a child of the clone
-- Let's select the first child of the clone
local clone_child = clone.children[1]
c_state.selected_node_id = clone_child.id
init.add_sibling(c_state)

root, src, clone = get_live_clone_nodes()
-- Adding sibling to clone_child (origin's child) should add sibling to the origin's child
assert(#src.children[1].parent.children == 3, "Sibling should be added to origin children list")
assert(#clone.children[1].parent.children == 3, "Sibling should propagate to clone children list")

-- 3. Test delete_node on a child of the clone
-- Select the newly added sibling
local sibling = clone.children[2]
c_state.selected_node_id = sibling.id
init.delete_node(c_state)

root, src, clone = get_live_clone_nodes()
assert(#src.children == 2, "Deleted node should be removed from source")
assert(#clone.children == 2, "Deleted node should be removed from clone")

print("Clone mutation propagation tests passed!")

print("----------------------------------------")
print("Running file-comparison integration tests...")

local render = require("mindmap.render")
local files = {
  { name = "deep_tree", layout = "vertical" },
  { name = "wide_tree", layout = "vertical" },
  { name = "complex_tree", layout = "vertical" },
  { name = "mind_tree", layout = "vertical" },
  { name = "mind_tree_horizontal", input = "mind_tree", layout = "horizontal" },
  { name = "user_example", layout = "vertical" },
  { name = "split_tree", layout = "split" },
}

for _, entry in ipairs(files) do
  local input_file = entry.input or entry.name
  local input_path = "tests/" .. input_file .. ".mm"
  local expected_path = "tests/" .. entry.name .. ".txt"

  local lines = {}
  for line in io.lines(input_path) do
    table.insert(lines, line)
  end

  local root, _ = parser.parse_lines(lines)
  assert(root ~= nil, "Failed to parse: " .. input_path)

  local buf = vim.api.nvim_create_buf(false, true)
  render.render_map(buf, root, root.id, entry.layout)
  local rendered_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  vim.api.nvim_buf_delete(buf, { force = true })

  local expected_lines = {}
  for line in io.lines(expected_path) do
    table.insert(expected_lines, line)
  end

  assert(#rendered_lines == #expected_lines, string.format("Line count mismatch for %s: got %d, expected %d", entry.name, #rendered_lines, #expected_lines))
  for i = 1, #rendered_lines do
    assert(rendered_lines[i] == expected_lines[i], string.format("Mismatch in %s line %d:\nGot:      '%s'\nExpected: '%s'", entry.name, i, rendered_lines[i], expected_lines[i]))
  end
  print(string.format("File comparison for '%s' passed!", entry.name))
end

print("File comparison tests passed!")

print("----------------------------------------")
print("Running navigation tests...")

local nav_lines = {
  "- Root Node",
  "  - Child 1",
  "    - Grandchild 1",
  "  - Child 2",
}
local n_tree, n_node_by_id = parser.parse_lines(nav_lines)
local n_state = {
  src_buf = 999,
  map_bufnr = 888,
  tree = n_tree,
  node_by_id = n_node_by_id,
  layout = "vertical",
  selected_node_id = n_tree.id,
}

n_state.redraw = function(st)
  require("mindmap.layout").compute_layout(st.tree, {
    layout = st.layout,
    row_gap = 4,
    col_gap = 4,
    sibling_gap = 2,
    margin = 2,
  })
end

n_state.redraw(n_state)

local root = n_tree
local c1 = root.children[1]
local gc1 = c1.children[1]
local c2 = root.children[2]

-- Current selected: root
assert(n_state.selected_node_id == root.id)

-- In vertical layout:
-- j goes to child
init.navigate(n_state, "child")
assert(n_state.selected_node_id == c1.id, "j (child) should navigate to Child 1")

-- l goes to next sibling
init.navigate(n_state, "next_sibling")
assert(n_state.selected_node_id == c2.id, "l (next_sibling) should navigate to Child 2")

-- h goes to prev sibling
init.navigate(n_state, "prev_sibling")
assert(n_state.selected_node_id == c1.id, "h (prev_sibling) should navigate to Child 1")

-- j goes to child (Grandchild 1)
init.navigate(n_state, "child")
assert(n_state.selected_node_id == gc1.id, "j (child) should navigate to Grandchild 1")

-- k goes to parent
init.navigate(n_state, "parent")
assert(n_state.selected_node_id == c1.id, "k (parent) should navigate to Child 1")

print("Navigation tests passed!")

print("----------------------------------------")
print("Running clipboard yanking tests...")

local mock_lines = { "line 1", "line 2", "line 3" }
local map_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(map_buf, 0, -1, false, mock_lines)

local test_state = {
  map_bufnr = map_buf,
}

-- Clear register first
vim.fn.setreg("+", "")
init.yank_map(test_state)

local yanked = vim.fn.getreg("+")
assert(yanked == "line 1\nline 2\nline 3\n", "Yanked content does not match map buffer content")

vim.api.nvim_buf_delete(map_buf, { force = true })
print("Clipboard yanking tests passed!")

print("----------------------------------------")
print("Running show_help tests...")

-- Test show_help opens a floating window
local start_wins = vim.api.nvim_list_wins()
init.show_help()
local end_wins = vim.api.nvim_list_wins()

assert(#end_wins == #start_wins + 1, "Help window should have opened")

-- Close the help window
local help_win = nil
for _, w in ipairs(end_wins) do
  local found = false
  for _, sw in ipairs(start_wins) do
    if w == sw then
      found = true
      break
    end
  end
  if not found then
    help_win = w
    break
  end
end

assert(help_win ~= nil, "Could not find help window ID")
vim.api.nvim_win_close(help_win, true)
print("Show_help tests passed!")

print("----------------------------------------")
print("Running node collapse/folding tests...")

local collapse_lines = {
  "- Root Node",
  "  - Child 1",
  "    - Grandchild 1",
  "    - Grandchild 2",
  "  - Child 2",
}
local c_tree, c_node_by_id = parser.parse_lines(collapse_lines)
local c_state = {
  src_buf = 999,
  map_bufnr = 888,
  tree = c_tree,
  node_by_id = c_node_by_id,
  layout = "vertical",
  selected_node_id = c_tree.children[1].id, -- Select Child 1
}

local child1 = c_tree.children[1]
assert(#child1.children == 2, "Child 1 should have 2 children initially")
assert(child1.collapsed == nil, "Child 1 should not be collapsed initially")

-- Calculate layout before collapse
local initial_max_row, initial_max_col = layout.compute_layout(c_tree, { layout = "vertical", sibling_gap = 2, margin = 2 })

-- Toggle collapse
init.toggle_collapse(c_state)
assert(child1.collapsed == true, "Child 1 should now be collapsed")

-- Calculate layout after collapse
local collapsed_max_row, collapsed_max_col = layout.compute_layout(c_tree, { layout = "vertical", sibling_gap = 2, margin = 2 })

-- The layout size should change or at least the grandchildren should have no row/col assigned
assert(child1.children[1].row == nil, "Grandchild 1 should not have a row assigned since it's collapsed")
assert(child1.children[2].row == nil, "Grandchild 2 should not have a row assigned since it's collapsed")

-- Test display name modification in render
-- Mock rendering environment to check display name
local mock_buf = vim.api.nvim_create_buf(false, true)
require("mindmap.render").render_map(mock_buf, c_tree, c_state.selected_node_id, "vertical")
local mock_rendered_lines = vim.api.nvim_buf_get_lines(mock_buf, 0, -1, false)
vim.api.nvim_buf_delete(mock_buf, { force = true })

-- Search mock rendered lines for Child 1 text with indicator
local found_indicator = false
for _, line in ipairs(mock_rendered_lines) do
  if line:find("Child 1  ⊕") or line:find("Child 1 ⊕") then
    found_indicator = true
    break
  end
end
assert(found_indicator, "Rendered output should display collapse indicator ⊕")

-- Let's mock a proper buffer for sync_tree_with_path testing
local src_buf = vim.api.nvim_create_buf(false, true)
c_state.src_buf = src_buf
c_state.map_bufnr = vim.api.nvim_create_buf(false, true)

-- Re-sync
init.sync_tree_with_path(c_state, { 1 }) -- Path to Child 1
local new_child1 = c_state.tree.children[1]
assert(new_child1.collapsed == true, "Collapsed state should be preserved after tree sync")

-- Expand
init.toggle_collapse(c_state)
assert(new_child1.collapsed == false, "Child 1 should be expanded again")

-- Re-sync again
init.sync_tree_with_path(c_state, { 1 })
local expanded_child1 = c_state.tree.children[1]
assert(expanded_child1.collapsed == false, "Expanded state should be preserved after tree sync")

vim.api.nvim_buf_delete(c_state.src_buf, { force = true })
vim.api.nvim_buf_delete(c_state.map_bufnr, { force = true })

print("Node collapse/folding tests passed!")

print("----------------------------------------")
print("Running split layout tests...")

local split_lines = {
  "- Root Node",
  "  - Right Child 1",
  "    - Right Grandchild 1",
  "  - Left Child 2",
  "    - Left Grandchild 2",
}
local s_root, _ = parser.parse_lines(split_lines)
assert(s_root ~= nil)

-- Compute split layout
layout.compute_layout(s_root, {
  layout = "split",
  row_gap = 4,
  col_gap = 4,
  sibling_gap = 2,
  margin = 2,
})

-- Verify directions
local rc1 = s_root.children[1]
local lc2 = s_root.children[2]

assert(rc1.direction == "right", "First child should be right direction")
assert(rc1.children[1].direction == "right", "Right child's descendant should be right direction")

assert(lc2.direction == "left", "Second child should be left direction")
assert(lc2.children[1].direction == "left", "Left child's descendant should be left direction")

-- Verify coordinates (left side should grow leftwards, so cols should be smaller)
print(string.format("Root: col=%d", s_root.col))
print(string.format("Right child: col=%d", rc1.col))
print(string.format("Left child: col=%d", lc2.col))

assert(rc1.col > s_root.col, "Right child column should be greater than root column")
assert(lc2.col < s_root.col, "Left child column should be less than root column")

-- Verify descendants
assert(rc1.children[1].col > rc1.col, "Right grandchild column should be greater than right child column")
assert(lc2.children[1].col < lc2.col, "Left grandchild column should be less than left child column")

-- Verify spatial navigation in split layout
local split_state = {
  src_buf = 999,
  map_bufnr = 888,
  tree = s_root,
  node_by_id = {},
  layout = "split",
  selected_node_id = s_root.id,
}
local function index_nodes(node)
  split_state.node_by_id[node.id] = node
  for _, child in ipairs(node.children) do
    index_nodes(child)
  end
end
index_nodes(s_root)

-- Stub redraw
local redraw_called = 0
init.redraw = function() redraw_called = redraw_called + 1 end

-- At root, pressing 'h' should select first left child (Left Child 2)
vim.api.nvim_get_current_buf = function() return 999 end
init.states[999] = split_state

-- Locate the 'h' keymap function manually by calling the mapping logic
local captured_maps = {}
local orig_keymap_set = vim.keymap.set
vim.keymap.set = function(mode, key, fn, opts)
  captured_maps[key] = fn
end

init.setup_map_keymaps(888, 999)

-- Restore
vim.keymap.set = orig_keymap_set

local h_fn = captured_maps["h"]
local l_fn = captured_maps["l"]

assert(h_fn ~= nil, "h keymap function should be registered")
assert(l_fn ~= nil, "l keymap function should be registered")

-- Select root
split_state.selected_node_id = s_root.id

-- Press h at root -> should go to Left Child 2
h_fn(split_state)
assert(split_state.selected_node_id == lc2.id, "h at root should select Left Child 2")

-- Press h at Left Child 2 -> should go to its child (Left Grandchild 2)
h_fn(split_state)
assert(split_state.selected_node_id == lc2.children[1].id, "h at Left Child 2 should select Left Grandchild 2")

-- Press l at Left Grandchild 2 -> should go to parent (Left Child 2)
l_fn(split_state)
assert(split_state.selected_node_id == lc2.id, "l at Left Grandchild 2 should select Left Child 2")

-- Press l at Left Child 2 -> should go to parent (Root)
l_fn(split_state)
assert(split_state.selected_node_id == s_root.id, "l at Left Child 2 should select Root")

-- Press l at Root -> should go to Right Child 1
l_fn(split_state)
assert(split_state.selected_node_id == rc1.id, "l at Root should select Right Child 1")

-- Press l at Right Child 1 -> should go to Right Grandchild 1
l_fn(split_state)
assert(split_state.selected_node_id == rc1.children[1].id, "l at Right Child 1 should select Right Grandchild 1")

-- Press h at Right Grandchild 1 -> should go to parent (Right Child 1)
h_fn(split_state)
assert(split_state.selected_node_id == rc1.id, "h at Right Grandchild 1 should select Right Child 1")

-- Press h at Right Child 1 -> should go to parent (Root)
h_fn(split_state)
assert(split_state.selected_node_id == s_root.id, "h at Right Child 1 should select Root")

print("Split layout tests passed!")

print("----------------------------------------")
print("ALL TESTS PASSED SUCCESSFULLY!")
print("----------------------------------------")



