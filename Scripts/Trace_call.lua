-- trace_hook.lua
-- Trace des appels de fonctions Lua + arguments dans un log,
-- uniquement pour les fichiers dont le chemin contient "buff",
-- avec CALL + RET et indentation basée sur la profondeur réelle.

local ok, err = pcall(function()

  local dbg = debug
  if not dbg or not dbg.sethook then
    return  -- environnement trop bridé
  end

  -- Source de ce fichier (pour ignorer les fonctions déclarées ici)
  local THIS_SRC = nil
  do
    local info = dbg.getinfo(1, "S")
    THIS_SRC = info and info.short_src or nil
  end

  local LOG_PATH = "C:\\temp\\Where Winds Meet\\trace_calls.log"

  local f, ferr = io.open(LOG_PATH, "wb")
  if not f then
    return
  end

  local function write_line(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do
      parts[#parts+1] = tostring(select(i, ...))
    end
    f:write(table.concat(parts), "\n")
  end

  write_line("-- Trace des appels de fonctions Lua (filtré sur 'buff')")
  write_line("-- ", os.date("%Y-%m-%d %H:%M:%S"))
  write_line("")

  ---------------------------------------------------------------------------
  -- CONFIG FILTRES
  ---------------------------------------------------------------------------

  -- On ne trace que les fichiers dont le chemin contient ces substrings
  local TRACE_ONLY_SRC_SUBSTR = {
    "",
  }

  -- Fichiers / chemins à ignorer (short_src)
  local SKIP_SRC_PREFIXES = {
    "engine/Lib/",
    "hexm/client/trace.lua",
    "hexm/client/logger.lua",
    "hexm/common/strict.lua",
    "hexm/common/datetime_manager.lua",
    "hexm/common/data/dir_object.lua",
    "hexm/common/data/bin_data_object.lua",
    "engine/Lib/partial.lua",
    "hexm/client/entities/local/component/anim.lua",
    "hexm/client/manager/task_queue/",
  }

  -- Noms de fonctions à ignorer
  local SKIP_FUNC_NAMES = {
    newindexdot   = true,
    excepthook    = true,
    __G__TRACKBACK__ = true,
    repr          = true,
    len           = true,
    error         = true,
    get_trace_msg = true,
    show_trace    = true,
    format_datetime = true,
    now           = true,
    now_raw       = true,
  }

  -- On limite le nombre d'arguments loggés
  local MAX_ARGS = 10

  ---------------------------------------------------------------------------
  -- Helpers
  ---------------------------------------------------------------------------

  local string_format = string.format
  local string_rep    = string.rep

  local function safe_tostring(v)
    local t = type(v)
    if t == "string" then
      local s = v
      local max_len = 200
      local len = #s
      if len > max_len then
        s = s:sub(1, max_len) .. string_format("...<len=%d>", len)
      end
      return string_format("%q", s)
    elseif t == "number" or t == "boolean" or t == "nil" then
      return tostring(v)
    end

    local ok_t, s = pcall(tostring, v)
    if ok_t and type(s) == "string" then
      return s
    end
    return "<" .. t .. ">"
  end

  -- Pour éviter la récursion dans le hook
  local in_hook = false

  -- Calcule l'indentation en fonction de la profondeur réelle de la pile Lua
  local function get_indent()
    local depth = 0
    local level = 3  -- 1 = hook, 2 = fonction hookée, 3+ = appelants

    while true do
      local info = dbg.getinfo(level, "S")
      if not info then
        break
      end
      if info.what == "Lua" then
        depth = depth + 1
      end
      level = level + 1
    end

    -- On enlève 1 pour que le premier niveau ne soit pas déjà indenté
    if depth > 0 then
      depth = depth - 1
    end

    return string_rep("  ", depth)
  end

  -- Teste si on doit ignorer cet appel
  local function should_skip(info)
    local src = info.short_src or ""

    -- Ignorer le fichier du hook lui-même
    if THIS_SRC and src == THIS_SRC then
      return true
    end

    -- Ne garder que les fichiers dont le chemin contient "buff" (ou autre substring)
    local lower_src = src:lower()
    local ok_path = false
    for _, sub in ipairs(TRACE_ONLY_SRC_SUBSTR) do
      if lower_src:find(sub, 1, true) then
        ok_path = true
        break
      end
    end
    if not ok_path then
      return true
    end

    -- Ignorer certaines sources "classiques"
    for _, prefix in ipairs(SKIP_SRC_PREFIXES) do
      if src == prefix or src:sub(1, #prefix) == prefix then
        return true
      end
    end

    -- Ignorer certaines fonctions par nom
    local name = info.name
    if name and SKIP_FUNC_NAMES[name] then
      return true
    end

    return false
  end

  ---------------------------------------------------------------------------
  -- Hook
  ---------------------------------------------------------------------------

  local function hook(event, line)
    if in_hook then
      return
    end

    -- On ne traite que CALL / TAIL CALL / RETURN
    if event ~= "call" and event ~= "tail call" and event ~= "return" then
      return
    end

    in_hook = true

    -- Pour RETURN on n'a besoin que de nS (nom + source)
    local info
    if event == "return" then
      info = dbg.getinfo(2, "nS")
    else
      info = dbg.getinfo(2, "nSlu")
    end

    if not info or info.what ~= "Lua" or should_skip(info) then
      in_hook = false
      return
    end

    local func_name = info.name or "<anonymous>"
    local src       = info.short_src or "?"
    local linedef   = info.linedefined or -1

    local prefix = get_indent()

    if event == "return" then
      -- On ne peut PAS récupérer les valeurs de retour via sethook.
      write_line(string_format(
        "%sRET  %s (%s:%d)",
        prefix,
        func_name,
        src,
        linedef
      ))
      in_hook = false
      return
    end

    -- Event = "call" ou "tail call" → on log les arguments
    local args = {}

    local nparams = info.nparams or 0
    if nparams > MAX_ARGS then
      nparams = MAX_ARGS
    end

    for i = 1, nparams do
      local name, value = dbg.getlocal(2, i)
      if not name then break end
      args[#args+1] = string_format("%s=%s", name, safe_tostring(value))
    end

    if info.isvararg and #args < MAX_ARGS then
      local i = 1
      while #args < MAX_ARGS do
        local name, value = dbg.getlocal(2, -i)
        if not name then
          break
        end
        args[#args+1] = string_format("...%d=%s", i, safe_tostring(value))
        i = i + 1
      end
    end

    write_line(string_format(
      "%sCALL %s (%s:%d)  args: (%s)",
      prefix,
      func_name,
      src,
      linedef,
      table.concat(args, ", ")
    ))

    in_hook = false
  end

  ---------------------------------------------------------------------------
  -- Activation du hook
  ---------------------------------------------------------------------------

  dbg.sethook(hook, "cr")

  -- Création sûre dans un environnement strict :
  rawset(_G, "STOP_TRACE_HOOK", function()
    dbg.sethook(nil)
    write_line("")
    write_line("-- TRACE STOPPED at ", os.date("%Y-%m-%d %H:%M:%S"))
    f:flush()
    f:close()
  end)

end)

if not ok then
  local ef = io.open("C:\\temp\\Where Winds Meet\\trace_hook_error.txt", "wb")
  if ef then
    ef:write("Erreur dans trace_hook.lua:\n")
    ef:write(tostring(err), "\n")
    ef:close()
  end
end

