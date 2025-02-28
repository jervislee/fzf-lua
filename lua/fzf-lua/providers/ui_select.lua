local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"

local M = {}

local _opts = nil
local _opts_once = nil
local _old_ui_select = nil

M.is_registered = function()
  return vim.ui.select == M.ui_select
end

M.deregister = function(_, silent, noclear)
  if not _old_ui_select then
    if not silent then
      utils.info("vim.ui.select in not registered to fzf-lua")
    end
    return false
  end
  vim.ui.select = _old_ui_select
  _old_ui_select = nil
  -- do not empty _opts in case when
  -- resume from `lsp_code_actions`
  if not noclear then
    _opts = nil
  end
  return true
end

M.register = function(opts, silent, opts_once)
  -- save "once" opts sent from lsp_code_actions
  _opts_once = opts_once
  if vim.ui.select == M.ui_select then
    -- already registered
    if not silent then
      utils.info("vim.ui.select already registered to fzf-lua")
    end
    return false
  end
  _opts = opts
  _old_ui_select = vim.ui.select
  vim.ui.select = M.ui_select
  return true
end

M.ui_select = function(items, opts, on_choice)
  --[[
  -- Code Actions
  opts = {
    format_item = <function 1>,
    kind = "codeaction",
    prompt = "Code actions:"
  }
  items[1] = { 1, {
    command = {
      arguments = { {
          action = "add",
          key = "Lua.diagnostics.globals",
          uri = "file:///home/bhagwan/.dots/.config/awesome/rc.lua",
          value = "mymainmenu"
        } },
      command = "lua.setConfig",
      title = "Mark defined global"
    },
    kind = "quickfix",
    title = "Mark `mymainmenu` as defined global."
  } } ]]

  -- exit visual mode if needed
  local mode = vim.api.nvim_get_mode()
  if not mode.mode:match("^n") then
    utils.feed_keys_termcodes("<Esc>")
  end

  local entries = {}
  for i, e in ipairs(items) do
    table.insert(entries,
      ("%s. %s"):format(utils.ansi_codes.magenta(tostring(i)),
        opts.format_item and opts.format_item(e) or tostring(e)))
  end

  local prompt = opts.prompt
  if not prompt then
    prompt = "Select one of:"
  end

  _opts = _opts or {}
  _opts.fzf_opts = {
    ["--no-multi"]       = "",
    ["--prompt"]         = prompt:gsub(":%s?$", "> "),
    ["--preview-window"] = "hidden:right:0",
  }

  -- save items so we can access them from the action
  _opts._items = items
  _opts._on_choice = on_choice

  _opts.actions = vim.tbl_deep_extend("keep", _opts.actions or {},
    {
      ["default"] = function(selected, o)
        local idx = selected and tonumber(selected[1]:match("^(%d+).")) or nil
        o._on_choice(idx and o._items[idx] or nil, idx)
      end
    })

  config.set_action_helpstr(_opts.actions["default"], "accept-item")

  _opts.fn_selected = function(selected, o)
    config.set_action_helpstr(_opts.actions["default"], nil)

    if not selected then
      on_choice(nil, nil)
    else
      actions.act(_opts.actions, selected, o)
    end

    if _opts.post_action_cb then
      _opts.post_action_cb()
    end
  end

  -- was this triggered by lsp_code_actions?
  local opts_once = _opts_once
  if _opts_once then
    -- merge and clear the once opts sent from lsp_code_actions.
    -- We also override actions to guarantee a single default
    -- action, otherwise selected[1] will be empty due to
    -- multiple keybinds trigger, sending `--expect` to fzf
    _opts_once.actions = _opts.actions
    opts_once = vim.tbl_deep_extend("keep", _opts_once, _opts)
    _opts_once = nil
  end

  core.fzf_exec(entries, opts_once or _opts)
end

return M
