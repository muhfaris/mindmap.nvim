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
  pattern = { "mindmap", "markdown" },
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

    -- Buffer-local help mapping
    vim.keymap.set("n", "?", function()
      require("mindmap").show_help()
    end, {
      buffer = ev.buf,
      silent = true,
      desc = "Show Mindmap Help Popup",
    })

    local ft = vim.api.nvim_get_option_value("filetype", { buf = ev.buf })
    if ft == "markdown" then
      local config = require("mindmap").config
      if config and config.auto_preview then
        local preview_group = vim.api.nvim_create_augroup("MindmapAutoPreview_" .. ev.buf, { clear = true })
        vim.api.nvim_create_autocmd({ "CursorMoved", "TextChanged", "TextChangedI" }, {
          group = preview_group,
          buffer = ev.buf,
          callback = function()
            require("mindmap").handle_markdown_autocmds()
          end,
        })
      end
    end
  end,
})
