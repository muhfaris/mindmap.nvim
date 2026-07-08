if vim.g.loaded_mindmap == 1 then
  return
end
vim.g.loaded_mindmap = 1

-- Register the .mm filetype
vim.filetype.add({
  extension = {
    mm = "mindmap",
  },
})

-- Autocmd to set up keymaps and commands for mindmap files
local group = vim.api.nvim_create_augroup("Mindmap", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "mindmap",
  callback = function(ev)
    -- Buffer-local toggle command
    vim.api.nvim_buf_create_user_command(ev.buf, "MindmapToggle", function()
      require("mindmap").toggle()
    end, {})

    -- Buffer-local toggle layout command
    vim.api.nvim_buf_create_user_command(ev.buf, "MindmapToggleLayout", function()
      require("mindmap").toggle_layout()
    end, {})

    -- Buffer-local toggle mapping
    vim.keymap.set("n", "gm", "<cmd>MindmapToggle<CR>", {
      buffer = ev.buf,
      silent = true,
      desc = "Toggle Mindmap View (Outline <-> Map)",
    })

    -- Buffer-local toggle layout mapping
    vim.keymap.set("n", "gl", "<cmd>MindmapToggleLayout<CR>", {
      buffer = ev.buf,
      silent = true,
      desc = "Toggle Mindmap Layout (Vertical <-> Horizontal)",
    })
  end,
})
