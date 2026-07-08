-- Script to generate rendered map output files for verification
-- Run with: nvim --headless -c "set rtp+=." -c "luafile lua/mindmap/generate_test_outputs.lua" -c "qa!"

local parser = require("mindmap.parser")
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
  local output_path = "tests/" .. entry.name .. ".txt"

  -- Read lines from input file
  local lines = {}
  for line in io.lines(input_path) do
    table.insert(lines, line)
  end

  -- Parse tree
  local root, _ = parser.parse_lines(lines)
  if root then
    -- Create dummy buffer
    local buf = vim.api.nvim_create_buf(false, true)
    
    -- Render map into dummy buffer
    render.render_map(buf, root, root.id, entry.layout) -- select root node
    
    -- Get rendered lines
    local rendered_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    
    -- Write to output file
    local out_f = io.open(output_path, "w")
    if out_f then
      out_f:write(table.concat(rendered_lines, "\n") .. "\n")
      out_f:close()
      print("Generated: " .. output_path)
    else
      print("Failed to write to: " .. output_path)
    end
    
    -- Delete dummy buffer
    vim.api.nvim_buf_delete(buf, { force = true })
  else
    print("Failed to parse: " .. input_path)
  end
end

print("Test output generation complete!")
