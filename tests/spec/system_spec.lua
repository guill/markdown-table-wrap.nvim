local h = require("tests.helpers")

local function is_concealed(details)
  return details.conceal == "" or details.conceal_lines == ""
end

h.test("system render chain only conceals detected table range", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
    max_col_width = 14,
    min_col_width = 4,
    row_separator = true,
    inline_viewport_scrolling = false,
  })

  h.with_buffer({
    "pipe prose | should stay visible",
    "| A | B |",
    "| --- | --- |",
    "| `code` | [link](url)<br>**bold** |",
    "after",
  }, function(buf)
    vim.bo[buf].filetype = "markdown"
    plugin.refresh_auto({ force = true })

    local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
    local concealed_rows = {}
    local styled = {}

    for _, mark in ipairs(marks) do
      local row = mark[2]
      local details = mark[4] or {}
      if is_concealed(details) then
        concealed_rows[row] = true
      end
      for _, chunk in ipairs(details.virt_text or {}) do
        styled[chunk[2]] = true
      end
      for _, virt_line in ipairs(details.virt_lines or {}) do
        for _, chunk in ipairs(virt_line) do
          styled[chunk[2]] = true
        end
      end
    end

    h.assert_false("adjacent prose is not concealed", concealed_rows[0])
    h.assert_true("header concealed", concealed_rows[1])
    h.assert_true("separator concealed", concealed_rows[2])
    h.assert_true("row concealed", concealed_rows[3])
    h.assert_true("code styled through chain", styled.MarkdownTableWrapCode)
    h.assert_true("link styled through chain", styled.MarkdownTableWrapLink)
    h.assert_true("bold styled through chain", styled.MarkdownTableWrapBold)

    inline.clear(buf)
  end)
end)

h.test("custom filetype configured via setup is rendered", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
    max_col_width = 14,
    min_col_width = 4,
    row_separator = true,
    inline_viewport_scrolling = false,
    filetypes = { "markdown", "md", "quarto", "rmarkdown", "opencode_output" },
  })

  h.with_buffer({
    "prose before",
    "| A | B |",
    "| --- | --- |",
    "| `code` | **bold** |",
    "prose after",
  }, function(buf)
    vim.bo[buf].filetype = "opencode_output"
    plugin.refresh_auto({ force = true })

    local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
    local concealed_rows = {}
    for _, mark in ipairs(marks) do
      local row = mark[2]
      local details = mark[4] or {}
      if is_concealed(details) then
        concealed_rows[row] = true
      end
    end

    h.assert_true("custom-filetype header concealed", concealed_rows[1])
    h.assert_true("custom-filetype separator concealed", concealed_rows[2])
    h.assert_true("custom-filetype row concealed", concealed_rows[3])

    inline.clear(buf)
  end)
end)

h.test("filetypes not in config are skipped", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
    inline_viewport_scrolling = false,
    filetypes = { "markdown" },
  })

  h.with_buffer({
    "| A | B |",
    "| --- | --- |",
    "| x | y |",
  }, function(buf)
    vim.bo[buf].filetype = "opencode_output"
    plugin.refresh_auto({ force = true })

    local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
    h.assert_eq("non-allowed filetype renders nothing", #marks, 0)

    inline.clear(buf)
  end)
end)

if vim.fn.has("nvim-0.11") == 1 then
  h.test("nvim-0.11+ uses repeat_linebreak overlay and preserves wrap", function()
    local plugin = require("markdown-table-wrap")
    local inline = require("markdown-table-wrap.inline")

    plugin.setup({
      debounce_ms = 0,
      render_all = true,
      auto_preview = true,
      inline_viewport_scrolling = false,
    })

    h.with_buffer({
      "prose before",
      "| A | B |",
      "| --- | --- |",
      "| x | y |",
      "prose after",
    }, function(buf)
      vim.bo[buf].filetype = "markdown"
      vim.wo.wrap = true
      plugin.refresh_auto({ force = true })

      local marks = vim.api.nvim_buf_get_extmarks(buf, inline.namespace(), 0, -1, { details = true })
      local has_conceal = false
      local has_repeat_linebreak = false
      local has_overlay = false
      for _, mark in ipairs(marks) do
        local details = mark[4] or {}
        if details.conceal == "" then
          has_conceal = true
        end
        if details.virt_text_repeat_linebreak then
          has_repeat_linebreak = true
        end
        if details.virt_text_pos == "overlay" then
          has_overlay = true
        end
      end

      h.assert_true("uses legacy conceal to hide source text", has_conceal)
      h.assert_true("uses per-row overlay rendering", has_overlay)
      h.assert_true("emits virt_text_repeat_linebreak overlays on 0.11+", has_repeat_linebreak)
      h.assert_true("wrap preserved on 0.11+", vim.wo.wrap)

      inline.clear(buf)
    end)
  end)
end

h.test("refresh_auto renders a non-current buffer when window exists", function()
  local plugin = require("markdown-table-wrap")
  local inline = require("markdown-table-wrap.inline")

  plugin.setup({
    debounce_ms = 0,
    render_all = true,
    auto_preview = true,
    max_col_width = 14,
    min_col_width = 4,
    row_separator = true,
    inline_viewport_scrolling = false,
    filetypes = { "markdown", "opencode_output" },
  })

  local target_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[target_buf].buftype = "nofile"
  vim.bo[target_buf].filetype = "opencode_output"
  vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, {
    "prose before",
    "| A | B |",
    "| --- | --- |",
    "| x | y |",
    "prose after",
  })

  vim.cmd("split")
  local target_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(target_win, target_buf)

  local other_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[other_buf].buftype = "nofile"
  vim.cmd("wincmd p")
  vim.api.nvim_set_current_buf(other_buf)

  h.assert_true("test setup: target buffer is not current", vim.api.nvim_get_current_buf() ~= target_buf)

  plugin.refresh_auto({ bufnr = target_buf, force = true })

  local marks = vim.api.nvim_buf_get_extmarks(target_buf, inline.namespace(), 0, -1, { details = true })
  local concealed_rows = {}
  for _, mark in ipairs(marks) do
    local row = mark[2]
    local details = mark[4] or {}
    if is_concealed(details) then
      concealed_rows[row] = true
    end
  end

  h.assert_true("cross-buffer render: header concealed", concealed_rows[1])
  h.assert_true("cross-buffer render: row concealed", concealed_rows[3])

  inline.clear(target_buf)
  if vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_win_close(target_win, true)
  end
  if vim.api.nvim_buf_is_valid(target_buf) then
    vim.api.nvim_buf_delete(target_buf, { force = true })
  end
  if vim.api.nvim_buf_is_valid(other_buf) then
    vim.api.nvim_buf_delete(other_buf, { force = true })
  end
end)

h.test("refresh_auto silently no-ops on invalid bufnr", function()
  local plugin = require("markdown-table-wrap")
  plugin.setup({ debounce_ms = 0 })

  local ok = pcall(plugin.refresh_auto, { bufnr = 99999, force = true })
  h.assert_true("refresh_auto tolerates invalid buffer", ok)
end)

h.test("invalid filetypes config falls back to defaults", function()
  local plugin = require("markdown-table-wrap")

  plugin.setup({
    filetypes = "not a table",
  })
  h.assert_eq("string filetypes falls back to 4 defaults", #plugin.config.filetypes, 4)

  plugin.setup({
    filetypes = {},
  })
  h.assert_eq("empty filetypes falls back to 4 defaults", #plugin.config.filetypes, 4)

  plugin.setup({
    filetypes = { 42, "", false, "markdown" },
  })
  h.assert_eq("filetypes filters non-string entries", #plugin.config.filetypes, 1)
  h.assert_eq("filetypes keeps the valid entry", plugin.config.filetypes[1], "markdown")
end)

h.test("plugin loader does not override manual setup", function()
  local plugin = require("markdown-table-wrap")
  local plugin_file = vim.fn.fnamemodify("plugin/markdown-table-wrap.lua", ":p")

  vim.g.loaded_markdown_table_wrap = nil
  plugin.state.did_setup = false

  plugin.setup({
    table_border = "single",
    row_separator = false,
    highlight_preset = "default",
    inline_viewport_scrolling = false,
  })

  dofile(plugin_file)

  h.assert_eq("manual table_border preserved", plugin.config.table_border, "single")
  h.assert_false("manual row_separator preserved", plugin.config.row_separator)
  h.assert_eq("manual highlight_preset preserved", plugin.config.highlight_preset, "default")
  h.assert_false("manual viewport preference preserved", plugin.config.inline_viewport_scrolling)
end)
