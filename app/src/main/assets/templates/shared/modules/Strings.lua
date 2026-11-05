-- Strings: local S = require "mods.Strings". Loading never changes string/table.
-- All indices and widths are Unicode CODE POINTS, not bytes, UTF-16 units,
-- grapheme clusters or display columns. Inputs must be valid UTF-8 strings.
-- length/len, charAt/get/at, slice, codePointAt, codePointBefore,
-- codePointCount and toCharArray use 1-based indices; negatives count from
-- the end. slice/count ranges are inclusive and clipped like utf8.sub.
-- charAt outside the string returns ""; codePointAt/Before return nil.
-- contains/startsWith/endsWith/removePrefix/removeSuffix/count are literal;
-- count counts non-overlapping occurrences (empty needle: length + 1).
-- split(s, delimiter, limit) is literal and preserves ALL empty fields.
-- nil/0/negative limit means unlimited; positive limit is maximum field count,
-- reserving the last field for the untouched remainder. Empty input => {""}
-- except empty delimiter: split("ab", "") => {"","a","b",""},
-- split("", "") => {"",""}. Empty delimiter matches every boundary.
-- splitPattern has identical limits, using Lua patterns (NOT Java regex).
-- Zero-width matches consume no text; search advances one code point to avoid
-- loops. Captures are ignored. Patterns use this runtime's utf8.find rules.
-- join(delimiter, list or ...), trim/trimLeading/trimTrailing/isBlank (ASCII
-- whitespace only), padStart/padEnd/center (repeat/truncate fill to width),
-- ellipsize(s, width, marker="…") (width includes marker), lines (CRLF/CR/LF,
-- preserving empty lines), lower/upper/equalsIgnoreCase (utf8 lowercase
-- comparison, NOT Unicode case folding), capitalize, concat/plus, isEmpty,
-- isNone, repeatText, indent, expandTabs (fixed spaces, not tab stops),
-- transform(s, fn) are also available. No Java dependency or shared state.
-- Compatibility is explicit: installLegacy([target=string]) copies helpers
-- and aliases (including ["repeat"]) to target and returns target. It does
-- NOT replace standard len/find/gsub/lower/upper or mutate table.
-- Legacy split is now literal and preserves empties; use splitPattern for
-- patterns. Index semantics above replace the old mixed UTF-16 behavior.
-- Unimplemented caseFold/findLast and Java compareTo/hashCode are not exposed.

local ulen, usub, ufind = utf8.len, utf8.sub, utf8.find
local ubyte, ulower, uupper = utf8.byte, utf8.lower, utf8.upper
local concat, rep = table.concat, string.rep
local S = {}

local function integer(value, name)
  assert(type(value) == "number" and value == math.floor(value)
    and value ~= math.huge and value ~= -math.huge, name .. " must be a finite integer")
  return value
end
local function index(value, size)
  integer(value, "index")
  if value < 0 then return size + value + 1 end
  return value
end
local function range(s, first, last)
  local size = ulen(s)
  first = math.max(1, index(first or 1, size))
  last = math.min(size, index(last or size, size))
  return first, last
end
S.length, S.len = ulen, ulen
function S.slice(s, first, last)
  first, last = range(s, first, last)
  if first > last then return "" end
  return usub(s, first, last)
end
function S.charAt(s, i)
  i = index(i, ulen(s))
  if i < 1 or i > ulen(s) then return "" end
  return usub(s, i, i)
end
function S.codePointAt(s, i)
  i = index(i, ulen(s))
  if i < 1 or i > ulen(s) then return nil end
  return ubyte(s, i, i)
end
function S.codePointBefore(s, i)
  i = index(i, ulen(s)) - 1
  if i < 1 then return nil end
  return S.codePointAt(s, i)
end
function S.codePointCount(s, first, last)
  first, last = range(s, first, last)
  return math.max(0, last - first + 1)
end
function S.toCharArray(s)
  local result = {}
  for i = 1, ulen(s) do result[i] = usub(s, i, i) end
  return result
end
function S.contains(s, needle) return ufind(s, needle, 1, true) ~= nil end
function S.startsWith(s, prefix) return S.slice(s, 1, ulen(prefix)) == prefix end
function S.endsWith(s, suffix)
  local n, m = ulen(s), ulen(suffix)
  return m <= n and S.slice(s, n - m + 1, n) == suffix
end
function S.removePrefix(s, prefix)
  if S.startsWith(s, prefix) then return S.slice(s, ulen(prefix) + 1) end
  return s
end
function S.removeSuffix(s, suffix)
  if S.endsWith(s, suffix) then return S.slice(s, 1, ulen(s) - ulen(suffix)) end
  return s
end
function S.count(s, needle)
  if needle == "" then return ulen(s) + 1 end
  local total, pos = 0, 1
  while true do
    local first, last = ufind(s, needle, pos, true)
    if not first then return total end
    total, pos = total + 1, last + 1
  end
end
local function split(s, delimiter, limit, plain)
  limit = integer(limit or 0, "limit")
  local result, cursor, search = {}, 1, 1
  local size = ulen(s)
  while search <= size + 1 and (limit <= 0 or #result < limit - 1) do
    local first, last = ufind(s, delimiter, search, plain)
    if not first then break end
    result[#result + 1] = S.slice(s, cursor, first - 1)
    cursor = last + 1
    if last < first then search = first + 1 else search = last + 1 end
  end
  result[#result + 1] = S.slice(s, cursor)
  return result
end
function S.split(s, delimiter, limit) return split(s, delimiter, limit, true) end
function S.splitPattern(s, pattern, limit) return split(s, pattern, limit, false) end
function S.join(delimiter, ...)
  local args = {...}
  if type(args[1]) == "table" then args = args[1] end
  return concat(args, delimiter)
end
local whitespace = { [9]=true, [10]=true, [11]=true, [12]=true, [13]=true, [32]=true }
function S.trimLeading(s)
  local i, n = 1, ulen(s)
  while i <= n and whitespace[ubyte(s, i, i)] do i = i + 1 end
  return S.slice(s, i)
end
function S.trimTrailing(s)
  local i = ulen(s)
  while i > 0 and whitespace[ubyte(s, i, i)] do i = i - 1 end
  return S.slice(s, 1, i)
end
function S.trim(s) return S.trimTrailing(S.trimLeading(s)) end
function S.isBlank(s) return S.trim(s) == "" end
function S.isEmpty(s) return s == nil or s == "" end
function S.isNone(s) return s == "" end
local function width(value) return math.max(0, integer(value, "width")) end
local function padding(fill, count)
  fill = fill or " "
  local n = ulen(fill)
  assert(n > 0, "fill must not be empty")
  if count <= 0 then return "" end
  return S.slice(rep(fill, math.ceil(count / n)), 1, count)
end
function S.padStart(s, size, fill) return padding(fill, width(size) - ulen(s)) .. s end
function S.padEnd(s, size, fill) return s .. padding(fill, width(size) - ulen(s)) end
function S.center(s, size, fill)
  local extra = math.max(0, width(size) - ulen(s))
  local left = math.floor(extra / 2)
  return padding(fill, left) .. s .. padding(fill, extra - left)
end
function S.ellipsize(s, size, marker)
  size, marker = width(size), marker or "…"
  if ulen(s) <= size then return s end
  if ulen(marker) >= size then return S.slice(marker, 1, size) end
  return S.slice(s, 1, size - ulen(marker)) .. marker
end
function S.lines(s)
  local result, start, i, n = {}, 1, 1, ulen(s)
  while i <= n do
    local ch = ubyte(s, i, i)
    if ch == 13 or ch == 10 then
      result[#result + 1] = S.slice(s, start, i - 1)
      if ch == 13 and i < n and ubyte(s, i + 1, i + 1) == 10 then i = i + 1 end
      start = i + 1
    end
    i = i + 1
  end
  result[#result + 1] = S.slice(s, start)
  return result
end
S.lower, S.upper = ulower, uupper
function S.equalsIgnoreCase(a, b) return ulower(a) == ulower(b) end
function S.capitalize(s) return uupper(S.charAt(s, 1)) .. S.slice(s, 2) end
function S.concat(s, other) return s .. other end
function S.repeatText(s, count) return rep(s, width(count)) end
function S.indent(s, count)
  local prefix = rep(" ", width(count))
  return prefix .. S.join("\n" .. prefix, S.split(s, "\n"))
end
function S.expandTabs(s, size) return S.join(rep(" ", width(size or 4)), S.split(s, "\t")) end
function S.transform(s, fn) return fn(s) end
S.get, S.at, S.plus = S.charAt, S.charAt, S.concat
S["repeat"] = S.repeatText
function S.installLegacy(target)
  target = target or string
  for name, fn in pairs(S) do
    if name ~= "installLegacy" and name ~= "len" and name ~= "lower" and name ~= "upper" then
      target[name] = fn
    end
  end
  return target
end
return S
