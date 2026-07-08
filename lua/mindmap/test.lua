-- Headless tests for mindmap.nvim
-- Run with: nvim --headless -c "set rtp+=." -c "luafile lua/mindmap/test.lua" -c "qa!"

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
print("Running state operations tests...")

local init = require("mindmap")

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

-- Test indent_node (Child 2 should become child of Child 1)
local c1 = tree.children[1]
local c2 = tree.children[2]
assert(c2.parent == tree)

init.indent_node(state)
assert(c2.parent == c1, "Child 2 should now be child of Child 1")
assert(c2.depth == 2, "Child 2 depth should be updated to 2")
assert(#c1.children == 1, "Child 1 should have 1 child")
assert(c1.children[1] == c2)
assert(#tree.children == 1, "Root should now have 1 child")

-- Test outdent_node (Child 2 should become sibling of Child 1 under Root again)
init.outdent_node(state)
assert(c2.parent == tree, "Child 2 should be reparented to Root")
assert(c2.depth == 1, "Child 2 depth should be 1")
assert(#tree.children == 2, "Root should have 2 children again")

-- Test add_child to Child 1
state.selected_node_id = c1.id
init.edit_node = function() end -- Stub out window float editor

init.add_child(state)
assert(#c1.children == 1, "Child 1 should have a new child")
local new_child = c1.children[1]
assert(new_child.text == "New Node", "Default text should be 'New Node'")
assert(new_child.depth == 2)
assert(state.selected_node_id == new_child.id, "New child should be selected")

-- Test add_sibling
init.add_sibling(state)
assert(#c1.children == 2, "Child 1 should now have 2 children")
local sibling = c1.children[2]
assert(sibling.text == "New Node")
assert(sibling.depth == 2)
assert(state.selected_node_id == sibling.id, "New sibling should be selected")

-- Test delete_node
init.delete_node(state)
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
assert(state.layout == "vertical", "Layout should toggle back to vertical")

vim.api.nvim_get_current_buf = orig_get_buf
init.redraw = orig_redraw

print("State operations tests passed!")

print("----------------------------------------")
print("Running file-comparison integration tests...")

local render = require("mindmap.render")
local files = {
  { name = "deep_tree", layout = "vertical" },
  { name = "wide_tree", layout = "vertical" },
  { name = "complex_tree", layout = "vertical" },
  { name = "mind_tree", layout = "vertical" },
  { name = "mind_tree_horizontal", input = "mind_tree", layout = "horizontal" },
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
print("ALL TESTS PASSED SUCCESSFULLY!")
print("----------------------------------------")


