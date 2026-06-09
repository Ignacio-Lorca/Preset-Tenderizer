-- Minimal JSON encoder/decoder for Preset Tenderizer (Lua 5.1+)
local json = {}

local escape_map = {
  ["\\"] = "\\\\",
  ["\""] = "\\\"",
  ["\b"] = "\\b",
  ["\f"] = "\\f",
  ["\n"] = "\\n",
  ["\r"] = "\\r",
  ["\t"] = "\\t",
}

local function escape_str(s)
  s = tostring(s)
  local out = {}

  for i = 1, #s do
    local c = s:sub(i, i)
    local mapped = escape_map[c]
    if mapped then
      out[#out + 1] = mapped
    else
      local byte = s:byte(i)
      if byte < 32 then
        out[#out + 1] = string.format("\\u%04x", byte)
      else
        out[#out + 1] = c
      end
    end
  end

  return table.concat(out)
end

function json.encode(value)
  local t = type(value)
  if t == "nil" then
    return "null"
  elseif t == "boolean" then
    return value and "true" or "false"
  elseif t == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      return "null"
    end
    return tostring(value)
  elseif t == "string" then
    return '"' .. escape_str(value) .. '"'
  elseif t == "table" then
    local is_array = true
    local max_index = 0
    for k, _ in pairs(value) do
      if type(k) ~= "number" then
        is_array = false
        break
      end
      if k > max_index then
        max_index = k
      end
    end
    if is_array and max_index == #value then
      local parts = {}
      for i = 1, #value do
        parts[i] = json.encode(value[i])
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local parts = {}
    for k, v in pairs(value) do
      table.insert(parts, json.encode(tostring(k)) .. ":" .. json.encode(v))
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  error("unsupported type: " .. t)
end

local function skip_ws(s, i)
  while true do
    local c = s:sub(i, i)
    if c == "" or not c:match("%s") then
      return i
    end
    i = i + 1
  end
end

local function parse_value(s, i)
  i = skip_ws(s, i)
  local c = s:sub(i, i)
  if c == "{" then
    local obj = {}
    i = i + 1
    i = skip_ws(s, i)
    if s:sub(i, i) == "}" then
      return obj, i + 1
    end
    while true do
      local key
      key, i = parse_value(s, i)
      i = skip_ws(s, i)
      if s:sub(i, i) ~= ":" then
        error("expected ':' at " .. i)
      end
      i = skip_ws(s, i + 1)
      local val
      val, i = parse_value(s, i)
      obj[key] = val
      i = skip_ws(s, i)
      local sep = s:sub(i, i)
      if sep == "}" then
        return obj, i + 1
      elseif sep ~= "," then
        error("expected ',' or '}' at " .. i)
      end
      i = skip_ws(s, i + 1)
    end
  elseif c == "[" then
    local arr = {}
    i = i + 1
    i = skip_ws(s, i)
    if s:sub(i, i) == "]" then
      return arr, i + 1
    end
    while true do
      local val
      val, i = parse_value(s, i)
      table.insert(arr, val)
      i = skip_ws(s, i)
      local sep = s:sub(i, i)
      if sep == "]" then
        return arr, i + 1
      elseif sep ~= "," then
        error("expected ',' or ']' at " .. i)
      end
      i = skip_ws(s, i + 1)
    end
  elseif c == '"' then
    local j = i + 1
    local out = {}
    while j <= #s do
      local ch = s:sub(j, j)
      if ch == '"' then
        return table.concat(out), j + 1
      elseif ch == "\\" then
        local esc = s:sub(j + 1, j + 1)
        if esc == "u" then
          local hex = s:sub(j + 2, j + 5)
          table.insert(out, string.char(tonumber(hex, 16)))
          j = j + 6
        else
          local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ["\\"] = "\\", ['"'] = '"' }
          table.insert(out, map[esc] or esc)
          j = j + 2
        end
      else
        table.insert(out, ch)
        j = j + 1
      end
    end
    error("unterminated string")
  elseif s:sub(i, i + 3) == "true" then
    return true, i + 4
  elseif s:sub(i, i + 4) == "false" then
    return false, i + 5
  elseif s:sub(i, i + 3) == "null" then
    return nil, i + 4
  else
    local num = s:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", i)
    if num then
      return tonumber(num), i + #num
    end
    error("unexpected token at " .. i)
  end
end

function json.decode(str)
  if not str or str == "" then
    return nil
  end
  local value, i = parse_value(str, 1)
  i = skip_ws(str, i)
  if i <= #str then
    error("trailing characters at " .. i)
  end
  return value
end

function json.read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  if not content or content == "" then
    return nil
  end
  return json.decode(content)
end

function json.write_file(path, value)
  local file = io.open(path, "w")
  if not file then
    return false
  end
  file:write(json.encode(value))
  file:close()
  return true
end

return json
