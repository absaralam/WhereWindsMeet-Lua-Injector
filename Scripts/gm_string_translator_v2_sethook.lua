-- gm_string_translator_v2_sethook.lua
-- Remplace à la volée les chaînes GM via un dictionnaire chargé depuis un fichier texte :
--  - desc des composants (CInt, CStr, Button, Label, CList, InputField, ... via gm_components.lua)
--  - labels/menu GM (str_to_index via gm_decorator.lua)
--  - data.name / data.desc / data.gm_index dans les items GM
--  - textes passés à Text:set_text(...)
--  - noms / valeurs des panneaux gm_watcher (MonitorPanel, add_watcher_func, render_cmd, render_value, ...)
-- via debug.sethook sur les CALL.
--
-- Log chaque remplacement dans gm_strings_log.txt.

if rawget(_G, "GM_STRING_TRANSLATOR_V2_INSTALLED") then
  return
end
_G.GM_STRING_TRANSLATOR_V2_INSTALLED = true

-----------------------------------------
-- Config : chemins
-----------------------------------------
local DICT_PATH = [[C:\temp\Where Winds Meet\gm_strings_dict.lua]]
local LOG_PATH  = [[C:\temp\Where Winds Meet\gm_strings_log.txt]]
local ENABLE_LOG = true

-----------------------------------------
-- Booléens pour activer / désactiver chaque hook
-----------------------------------------
local ENABLE = {
  gm_components_ctor          = true,
  gm_components_CInt          = true,
  gm_components_CFloat        = true,
  gm_components_CStr          = true,
  gm_components_CBool         = true,
  gm_components_CList         = true,
  gm_components_Button        = true,
  gm_components_Label         = true,
  gm_components_InputField    = true,

  gm_decorator_str_to_index   = true,
  gm_decorator_index_to_str   = true, -- non utilisé ici mais gardé

  gm_window_update_content    = true,

  listview_push_back_item     = true,
  listview_set_and_update     = true,

  view_base_add_child_view    = true,
  view_base_init              = true,

  gm_watcher_MonitorPanel     = true,
  gm_watcher_add_watcher_func = true,
  gm_watcher_render_cmd       = true,
  gm_watcher_eval_cmd         = true,
  gm_watcher_render_value     = true,

  text_set_text               = true,
}

-- Flag pour éviter la récursion du hook pendant les IO
local _IN_LOG = false

-----------------------------------------
-- Logging
-----------------------------------------
local function write_log_line(line)
  if not ENABLE_LOG then return end
  local f = io.open(LOG_PATH, "a")
  if f then
    f:write(line, "\n")
    f:close()
  end
end

local function log_change(where, old, new)
  if not ENABLE_LOG then return end
  if type(old) ~= "string" or type(new) ~= "string" then return end
  if old == new then return end
  if _IN_LOG then return end

  _IN_LOG = true
  local ts   = os.date("%Y-%m-%d %H:%M:%S")
  where = where or ""
  local ctx = where ~= "" and (" (" .. where .. ")") or ""
  write_log_line(string.format("%s\t%s\t=>\t%s%s", ts, old, new, ctx))
  _IN_LOG = false
end

-----------------------------------------
-- Chargement du dictionnaire en mode TEXTE
-- Supporte :
--   return {
--     ["clé"] = "valeur",
--     ...
--   }
-- ou bien juste :
--   ["clé"] = "valeur",
--   ["clé2"] = "valeur2",
-----------------------------------------
local TR_DICT = {}

do
  local f = io.open(DICT_PATH, "r")
  if not f then
    write_log_line(string.format(
      "%s\t[ERROR]\tCannot open dict file '%s'",
      os.date("%Y-%m-%d %H:%M:%S"),
      DICT_PATH
    ))
  else
    local content = f:read("*a")
    f:close()

    local count = 0

    -- On récupère toutes les paires ["clé"] = "valeur"
    -- Backslash, chinois, accents, etc. sont acceptés tels quels (pas d'escape Lua).
    for k, v in content:gmatch('%["(.-)"%]%s*=%s*"(.-)"%s*,?') do
      TR_DICT[k] = v
      count = count + 1
    end

    write_log_line(string.format(
      "%s\t[INFO]\tgm_string_translator_v2 loaded, dict entries = %d",
      os.date("%Y-%m-%d %H:%M:%S"), count
    ))
  end
end

-----------------------------------------
-- Utilitaires de traduction
-----------------------------------------
local function has_non_ascii(s)
  return type(s) == "string" and s:match("[\128-\255]") ~= nil
end

local function translate_string(s, where)
  if type(s) ~= "string" then return s end
  -- "Sélectionner", "将军祠", etc. ont des caractères > 127, donc OK.
  -- Si tu veux aussi traduire les ASCII purs, commente la ligne suivante.
  if not has_non_ascii(s) then return s end

  local t = TR_DICT[s]
  if t and t ~= "" and t ~= s then
    log_change(where, s, t)
    return t
  end
  return s
end

local function translate_table_strings(t, where, visited)
  if type(t) ~= "table" then return end
  visited = visited or {}
  if visited[t] then return end
  visited[t] = true

  for k, v in pairs(t) do
    if type(v) == "string" then
      local new = translate_string(v, where)
      if new ~= v then
        t[k] = new
      end
    elseif type(v) == "table" then
      translate_table_strings(v, where, visited)
    end
  end
end

-----------------------------------------
-- Hook global via debug.sethook
-----------------------------------------
local function hook(event)
  if event ~= "call" then
    return
  end
  if _IN_LOG then
    return
  end

  local info = debug.getinfo(2, "nSl")
  if not info then return end

  local src  = info.source or ""
  local name = info.name or ""

  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end

  -------------------------------------------------
  -- 1) gm_components.lua
  -------------------------------------------------
  if src:find("hexm/client/debug/gm/gm_components.lua", 1, true) then
    local enabled =
      (name == "ctor"       and ENABLE.gm_components_ctor)       or
      (name == "CInt"       and ENABLE.gm_components_CInt)       or
      (name == "CFloat"     and ENABLE.gm_components_CFloat)     or
      (name == "CStr"       and ENABLE.gm_components_CStr)       or
      (name == "CBool"      and ENABLE.gm_components_CBool)      or
      (name == "CList"      and ENABLE.gm_components_CList)      or
      (name == "Button"     and ENABLE.gm_components_Button)     or
      (name == "Label"      and ENABLE.gm_components_Label)      or
      (name == "InputField" and ENABLE.gm_components_InputField)

    if enabled then
      -- self = local 1, desc = local 2 (comme dans ton dump)
      local _, desc = debug.getlocal(2, 2)
      if type(desc) == "string" then
        local new = translate_string(desc, "gm_components:" .. (name or "?"))
        if new ~= desc then
          debug.setlocal(2, 2, new)
        end
      end
      return
    end
  end

  -------------------------------------------------
  -- 2) gm_decorator.lua : str_to_index("xxx")
  -------------------------------------------------
  if src:find("hexm/client/debug/gm/gm_decorator.lua", 1, true) then
    if name == "str_to_index" and ENABLE.gm_decorator_str_to_index then
      local _, str = debug.getlocal(2, 1)
      if type(str) == "string" then
        local new = translate_string(str, "gm_decorator:str_to_index")
        if new ~= str then
          debug.setlocal(2, 1, new)
        end
      end
      return
    end
  end

  -------------------------------------------------
  -- 3) gm_window.lua : update_content(self, key, data, ...)
  -------------------------------------------------
  if src:find("hexm/client/ui/windows/gm/gm_window.lua", 1, true) then
    if name == "update_content" and ENABLE.gm_window_update_content then
      local _, data = debug.getlocal(2, 3)
      if type(data) == "table" then
        if type(data.name) == "string" then
          local new = translate_string(data.name, "gm_window:update_content:name")
          if new ~= data.name then
            data.name = new
          end
        end
        if type(data.desc) == "string" then
          local new = translate_string(data.desc, "gm_window:update_content:desc")
          if new ~= data.desc then
            data.desc = new
          end
        end
        if type(data.gm_index) == "table" then
          translate_table_strings(data.gm_index, "gm_window:update_content:gm_index")
        end
      end
      return
    end
  end

  -------------------------------------------------
  -- 4) listview_controller.lua
  -------------------------------------------------
  if src:find("hexm/client/ui/controllers/listview_controller.lua", 1, true) then
    if name == "push_back_item" and ENABLE.listview_push_back_item then
      local _, data = debug.getlocal(2, 2)
      if type(data) == "table" then
        if type(data.name) == "string" then
          local new = translate_string(data.name, "listview:push_back_item:name")
          if new ~= data.name then
            data.name = new
          end
        end
        if type(data.desc) == "string" then
          local new = translate_string(data.desc, "listview:push_back_item:desc")
          if new ~= data.desc then
            data.desc = new
          end
        end
        if type(data.gm_index) == "table" then
          translate_table_strings(data.gm_index, "listview:push_back_item:gm_index")
        end
      end
      return

    elseif name == "set_and_update_content" and ENABLE.listview_set_and_update then
      local _, data = debug.getlocal(2, 3)
      if type(data) == "table" then
        if type(data.name) == "string" then
          local new = translate_string(data.name, "listview:set_and_update_content:name")
          if new ~= data.name then
            data.name = new
          end
        end
        if type(data.desc) == "string" then
          local new = translate_string(data.desc, "listview:set_and_update_content:desc")
          if new ~= data.desc then
            data.desc = new
          end
        end
        if type(data.gm_index) == "table" then
          translate_table_strings(data.gm_index, "listview:set_and_update_content:gm_index")
        end
      end
      return
    end
  end

  -------------------------------------------------
  -- 5) view_base.lua
  -------------------------------------------------
  if src:find("hexm/client/ui/struct/view_base.lua", 1, true) then
    if name == "add_child_view" and ENABLE.view_base_add_child_view then
      local _, kwargs = debug.getlocal(2, 3)
      if type(kwargs) == "table" then
        translate_table_strings(kwargs, "view_base:add_child_view:kwargs")
      end
      return

    elseif name == "init" and ENABLE.view_base_init then
      local _, kwargs = debug.getlocal(2, 2)
      if type(kwargs) == "table" then
        translate_table_strings(kwargs, "view_base:init:kwargs")
      end
      return
    end
  end

  -------------------------------------------------
  -- 6) gm_watcher.lua
  -------------------------------------------------
  if src:find("hexm/client/debug/gm/gm_watcher.lua", 1, true) then
    if name == "MonitorPanel" and ENABLE.gm_watcher_MonitorPanel then
      local _, panel_name = debug.getlocal(2, 2)
      if type(panel_name) == "string" then
        local new = translate_string(panel_name, "gm_watcher:MonitorPanel")
        if new ~= panel_name then
          debug.setlocal(2, 2, new)
        end
      end
      return

    elseif name == "add_watcher_func" and ENABLE.gm_watcher_add_watcher_func then
      local _, watcher_name = debug.getlocal(2, 2)
      if type(watcher_name) == "string" then
        local new = translate_string(watcher_name, "gm_watcher:add_watcher_func")
        if new ~= watcher_name then
          debug.setlocal(2, 2, new)
        end
      end
      return

    elseif name == "render_cmd" and ENABLE.gm_watcher_render_cmd then
      local _, cmd_item = debug.getlocal(2, 2)
      if type(cmd_item) == "table" then
        translate_table_strings(cmd_item, "gm_watcher:render_cmd")
      end
      return

    elseif name == "eval_cmd" and ENABLE.gm_watcher_eval_cmd then
      local _, cmd = debug.getlocal(2, 2)
      if type(cmd) == "table" then
        translate_table_strings(cmd, "gm_watcher:eval_cmd")
      end
      return

    elseif name == "render_value" and ENABLE.gm_watcher_render_value then
      local _, name_arg  = debug.getlocal(2, 2)
      local _, value_arg = debug.getlocal(2, 3)
      if type(name_arg) == "string" then
        local new = translate_string(name_arg, "gm_watcher:render_value:name")
        if new ~= name_arg then
          debug.setlocal(2, 2, new)
        end
      end
      if type(value_arg) == "string" then
        local new = translate_string(value_arg, "gm_watcher:render_value:value")
        if new ~= value_arg then
          debug.setlocal(2, 3, new)
        end
      end
      return
    end
  end

  -------------------------------------------------
  -- 7) text.lua : Text:set_text(self, s, ...)
  -------------------------------------------------
  if src:find("hexm/client/ui/base/text.lua", 1, true) then
    if name == "set_text" and ENABLE.text_set_text then
      local _, s = debug.getlocal(2, 2)
      if type(s) == "string" then
        local new = translate_string(s, "text:set_text")
        if new ~= s then
          debug.setlocal(2, 2, new)
        end
      end
      return
    end
  end
end

debug.sethook(hook, "c")
return true
