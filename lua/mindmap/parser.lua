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
        
        -- Detect anchor/link tags
        local anchor_id, actual_text = text:match("^%[id:([%w_%-]+)%]%s*(.*)$")
        local link_id = text:match("^%[link:([%w_%-]+)%]$")

        if anchor_id then
          node.anchor_id = anchor_id
          node.text = actual_text
        elseif link_id then
          node.link_id = link_id
          node.text = ""
        end

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

  local warnings = {}

  -- Resolve links
  if root then
    local anchors = {}
    local function find_anchors(node)
      if node.anchor_id then
        if anchors[node.anchor_id] then
          table.insert(warnings, {
            type = "duplicate_anchor",
            id = node.anchor_id,
            line = node.line_num or -1,
            message = string.format("Duplicate anchor '%s' defined on line %d", node.anchor_id, node.line_num or -1)
          })
        else
          anchors[node.anchor_id] = node
        end
      end
      for _, child in ipairs(node.children) do
        find_anchors(child)
      end
    end
    find_anchors(root)

    local function clone_subtree(orig, parent)
      local copy = Node.new(orig.text, parent.depth + 1, nil)
      copy.parent = parent
      copy.origin = orig
      copy.is_clone = true
      copy.link_id = orig.link_id
      copy.anchor_id = orig.anchor_id
      node_by_id[copy.id] = copy
      for _, child in ipairs(orig.children) do
        if not child.is_clone then
          local child_copy = clone_subtree(child, copy)
          table.insert(copy.children, child_copy)
        end
      end
      return copy
    end

    local detected_cycles = {}

    local function process_links(node, visited)
      if node.link_id then
        local link_name = node.link_id
        if visited[link_name] then
          node.text = "[link:" .. link_name .. "] (circular reference)"
          local cycle_members = {}
          for k, v in pairs(visited) do
            if v then
              table.insert(cycle_members, k)
            end
          end
          table.sort(cycle_members)
          local cycle_key = table.concat(cycle_members, "-")
          if not detected_cycles[cycle_key] then
            detected_cycles[cycle_key] = true
            table.insert(warnings, {
              type = "circular_reference",
              id = link_name,
              line = node.line_num or -1,
              message = string.format("Circular reference detected for link '%s' on line %d", link_name, node.line_num or -1)
            })
          end
          return
        end
        local target = anchors[link_name]
        if target then
          node.text = target.text
          node.origin = target
          visited[link_name] = true
          for _, child in ipairs(target.children) do
            local child_copy = clone_subtree(child, node)
            table.insert(node.children, child_copy)
          end
          -- Recursively process links inside the cloned children in case the target subtree had link nodes
          for _, child in ipairs(node.children) do
            process_links(child, visited)
          end
          visited[link_name] = nil
        else
          node.text = "[link:" .. link_name .. "] (broken link)"
          table.insert(warnings, {
            type = "broken_link",
            id = link_name,
            line = node.line_num or -1,
            message = string.format("Broken link '%s' on line %d (anchor not found)", link_name, node.line_num or -1)
          })
        end
      else
        for _, child in ipairs(node.children) do
          process_links(child, visited)
        end
      end
    end

    process_links(root, {})
  end

  return root, node_by_id, warnings
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
      if node.anchor_id then
        table.insert(lines, indent .. "- [id:" .. node.anchor_id .. "] " .. node.text)
      elseif node.link_id then
        table.insert(lines, indent .. "- [link:" .. node.link_id .. "]")
      else
        table.insert(lines, indent .. "- " .. node.text)
      end
      node.line_num = #lines -- update line_num based on new output position
    end

    if not node.link_id then
      for _, child in ipairs(node.children) do
        traverse(child)
      end
    end
  end

  if root then
    traverse(root)
  end

  return lines
end

return M
