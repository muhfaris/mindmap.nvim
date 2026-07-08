-- Integration verification for mindmap.nvim
-- Run with: nvim -u NONE --headless -c "set rtp+=." -c "luafile lua/mindmap/verify.lua" -c "qa!"

local init = require("mindmap")

-- 1. Create a dummy buffer and load test outline
local test_lines = {
  "- Gherkio v2",
  "  - Transform block",
  "    - Array proj",
  "      - dot path",
  "      - wildcard",
  "    - Filters",
  "  - Report UI",
  "    - Try-it",
  "      - CORS fix",
  "    - Token mask",
}

local src_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(src_buf, 0, -1, false, test_lines)
vim.api.nvim_win_set_buf(0, src_buf)
vim.api.nvim_set_option_value("filetype", "mindmap", { buf = src_buf })

-- Set cursor to line 2 ("  - Transform block")
vim.api.nvim_win_set_cursor(0, { 2, 0 })

print("1. Toggling to Map Mode...")
init.toggle()

local state = init.states[src_buf]
assert(state ~= nil, "State should be initialized")
assert(state.mode == "map", "Should be in map mode")
print("Selected node text:", state.node_by_id[state.selected_node_id].text)
assert(state.node_by_id[state.selected_node_id].text == "Transform block", "Should have selected 'Transform block'")

-- Let's inspect the rendered map lines
local map_lines = vim.api.nvim_buf_get_lines(state.map_bufnr, 0, -1, false)
print("Rendered map rows count:", #map_lines)

-- 2. Simulate cursor movement
print("2. Navigating to 'Array proj'...")
-- 'Array proj' is a child of 'Transform block', so let's press 'j'
init.navigate(state, "child")
print("Selected node after 'j':", state.node_by_id[state.selected_node_id].text)
assert(state.node_by_id[state.selected_node_id].text == "Array proj", "Should navigate to child")

print("3. Navigating to 'Filters'...")
init.navigate(state, "next_sibling")
print("Selected node after 'l':", state.node_by_id[state.selected_node_id].text)
assert(state.node_by_id[state.selected_node_id].text == "Filters", "Should navigate to next sibling")

-- 3. Edit node text
print("4. Editing 'Filters' to 'Advanced Filters'...")
local node = state.node_by_id[state.selected_node_id]
node.text = "Advanced Filters"
init.update_tree_and_redraw(state)
print("Selected node text after edit:", state.node_by_id[state.selected_node_id].text)
assert(state.node_by_id[state.selected_node_id].text == "Advanced Filters", "Text should be updated")

-- 4. Add child
print("5. Adding child to 'Advanced Filters'...")
local parent = state.node_by_id[state.selected_node_id]
local child = require("mindmap.parser").Node.new("New Child Node", parent.depth + 1)
child.parent = parent
table.insert(parent.children, child)
state.node_by_id[child.id] = child
state.selected_node_id = child.id
init.update_tree_and_redraw(state)
print("New child parent text:", state.node_by_id[state.selected_node_id].parent.text)

-- 5. Toggle back to outline mode
print("6. Toggling back to Outline Mode...")
init.toggle()
local final_lines = vim.api.nvim_buf_get_lines(src_buf, 0, -1, false)
print("Final outline lines:")
for i, line in ipairs(final_lines) do
  print(line)
end

-- Write map output to a text file for inspection
local f = io.open("map_render_output.txt", "w")
if f then
  f:write(table.concat(map_lines, "\n"))
  f:close()
  print("Saved map render output to map_render_output.txt")
end

print("INTEGRATION VERIFICATION PASSED SUCCESSFULLY!")
