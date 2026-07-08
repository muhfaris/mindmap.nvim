local M = {}

local Node = {}
Node.__index = Node

function Node.new(text, depth, line_num)
  return setmetatable({
    id = tostring(math.random(10000000, 99999999)),
    text = text or "",
    depth = depth or 0,
    children = {},
    parent = nil,
    line_num = line_num,
  }, Node)
end

-- Export the Node class/constructor for testing or editing
M.Node = Node

--- Parses an array of lines into a tree structure.
--- Returns the root node and a table of nodes by ID.
--- @param lines table List of strings
--- @return table|nil root The root Node
--- @return table node_by_id Map of id -> Node
function M.parse_lines(lines)
  local stack = {} -- array of { indent = number, node = Node }
  local root = nil
  local node_by_id = {}

  for line_idx, line in ipairs(lines) do
    if not line:match("^%s*$") then
      local indent_str, bullet, text = line:match("^(%s*)([-*+]?)%s*(.-)%s*$")
      if bullet ~= "" or text ~= "" then
        local indent = #indent_str
        if text == "" and bullet ~= "" then
          text = bullet
        end

        -- Find parent node in the stack
        while #stack > 0 and stack[#stack].indent >= indent do
          table.remove(stack)
        end

        local parent = nil
        local depth = 0
        if #stack > 0 then
          parent = stack[#stack].node
          depth = parent.depth + 1
        end

        local node = Node.new(text, depth, line_idx)
        node_by_id[node.id] = node

        if parent then
          node.parent = parent
          table.insert(parent.children, node)
        else
          if not root then
            root = node
          else
            -- We have multiple top-level nodes. Create/use a virtual root.
            if not root.is_virtual then
              local old_root = root
              root = Node.new("Workspace", 0, 0)
              root.is_virtual = true
              node_by_id[root.id] = root

              old_root.parent = root
              local function shift_depths(n, d)
                n.depth = d
                for _, child in ipairs(n.children) do
                  shift_depths(child, d + 1)
                end
              end
              shift_depths(old_root, 1)
              table.insert(root.children, old_root)
            end

            node.parent = root
            node.depth = 1
            table.insert(root.children, node)
          end
        end

        table.insert(stack, { indent = indent, node = node })
      end
    end
  end

  return root, node_by_id
end

--- Serializes a tree back into a list of indented strings.
--- Updates each node's `line_num` to match its new position in the serialized text.
--- @param root table The root Node
--- @param indent_size number? Number of spaces per indent level (default: 2)
--- @return table lines List of strings
function M.serialize_tree(root, indent_size)
  indent_size = indent_size or 2
  local lines = {}

  local function traverse(node)
    if not node.is_virtual then
      local depth = node.depth
      if root.is_virtual then
        depth = depth - 1
      end
      local indent = string.rep(" ", depth * indent_size)
      table.insert(lines, indent .. "- " .. node.text)
      node.line_num = #lines -- update line_num based on new output position
    end

    for _, child in ipairs(node.children) do
      traverse(child)
    end
  end

  if root then
    traverse(root)
  end

  return lines
end

return M
