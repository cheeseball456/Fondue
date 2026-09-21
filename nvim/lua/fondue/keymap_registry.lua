-- Keymap registry: registers every key from keymaps.lua and refuses to let one
-- key be bound twice, or a single key to hide a whole group.
--
-- On a problem it keeps the FIRST binding, shows an error naming both entries,
-- records the problem (so :checkhealth fondue can report it) and carries on.
-- A configuration that will not open is worse than one with a loud warning.
local M = {}

-- Everything registered so far, keyed by "mode\0token token token" -> entry.
local bound = {}
-- Every registered entry in order (keys and groups), used for prefix checks.
local entries = {}
-- Problems found: { kind = "duplicate" | "prefix" | "missing_desc" | "missing_field", message = "..." }
local problems = {}

-- Split a key sequence into tokens so "<leader>ab" and "<Space>ab" compare equal.
-- "<C-x>" is one token; a plain character is one token; a space is "<space>".
local function tokenize(lhs)
  local leader = vim.g.mapleader or "\\"
  lhs = lhs:gsub("<[Ll]eader>", function()
    return leader == " " and "<space>" or leader
  end)
  local out, i = {}, 1
  while i <= #lhs do
    local special = lhs:match("^<[^>]+>", i)
    if special then
      out[#out + 1] = special:lower()
      i = i + #special
    else
      local ch = lhs:sub(i, i)
      out[#out + 1] = ch == " " and "<space>" or ch
      i = i + 1
    end
  end
  return out
end

-- Is token list `a` a strict prefix of token list `b`?
local function is_strict_prefix(a, b)
  if #a >= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

local function describe(e)
  local kind = e.is_group and "group" or "key"
  return string.format("%s [%s] %s (%s)", kind, e.mode, e.lhs, e.desc or "no description")
end

local function report(kind, message)
  problems[#problems + 1] = { kind = kind, message = message }
  vim.notify("Fondue keymap problem: " .. message, vim.log.levels.ERROR)
end

-- Modes may be given as "n" or { "n", "x" }; default is normal mode.
local function modes_of(entry)
  local m = entry.mode or "n"
  return type(m) == "table" and m or { m }
end

-- Check one (mode, lhs) against everything already registered.
-- Returns true when it is safe to add.
local function check(candidate)
  local id = candidate.mode .. "\0" .. table.concat(candidate.tokens, " ")
  local first = bound[id]
  if first then
    report("duplicate", string.format("%s is already bound by %s", describe(candidate), describe(first)))
    return false
  end
  for _, other in ipairs(entries) do
    if other.mode == candidate.mode then
      -- A single key must not be a prefix of another key or group.
      if not other.is_group and is_strict_prefix(other.tokens, candidate.tokens) then
        report("prefix", string.format("%s is a prefix of %s, so it would hide it", describe(other), describe(candidate)))
        return false
      end
      if not candidate.is_group and is_strict_prefix(candidate.tokens, other.tokens) then
        report("prefix", string.format("%s is a prefix of %s, so it would hide it", describe(candidate), describe(other)))
        return false
      end
    end
  end
  return true
end

local function add(candidate)
  bound[candidate.mode .. "\0" .. table.concat(candidate.tokens, " ")] = candidate
  entries[#entries + 1] = candidate
end

-- Register the groups and keys from keymaps.lua. Safe to call again (state is reset).
function M.setup(spec)
  bound, entries, problems = {}, {}, {}

  -- Groups are declared first: they only label a prefix, they bind nothing.
  for _, g in ipairs(spec.groups or {}) do
    if type(g.prefix) ~= "string" or g.prefix == "" then
      report("missing_field", "a group has no prefix, so it was not registered")
    else
      for _, mode in ipairs(modes_of(g)) do
        local group = { mode = mode, lhs = g.prefix, desc = g.desc, tokens = tokenize(g.prefix), is_group = true }
        if check(group) then
          add(group)
        end
      end
    end
  end

  for _, k in ipairs(spec.keys or {}) do
    if type(k.lhs) ~= "string" or k.lhs == "" then
      report("missing_field", "a key entry has no lhs (the keys to press), so it was not registered")
    elseif not k.desc or k.desc == "" then
      report("missing_desc", string.format("key %s has no description, so it was not registered", k.lhs))
    elseif type(k.action) ~= "string" and type(k.action) ~= "function" then
      -- vim.keymap.set would throw here and stop startup, so report and skip instead.
      report("missing_field", string.format("key %s (%s) has no action, so it was not registered", k.lhs, k.desc))
    else
      for _, mode in ipairs(modes_of(k)) do
        local key = { mode = mode, lhs = k.lhs, desc = k.desc, tokens = tokenize(k.lhs) }
        if check(key) then
          add(key)
          vim.keymap.set(mode, k.lhs, k.action, { desc = k.desc, silent = true })
        end
      end
    end
  end

  M._spec = spec
end

-- The group labels in the shape which-key expects (its `spec` option).
function M.which_key_spec()
  local out = {}
  for _, g in ipairs((M._spec and M._spec.groups) or {}) do
    if type(g.prefix) == "string" and g.prefix ~= "" then
      out[#out + 1] = { g.prefix, group = g.desc, mode = g.mode or "n" }
    end
  end
  return out
end

-- Conflicts recorded at startup (duplicates, prefix clashes, missing descriptions).
function M.conflicts()
  return problems
end

return M
