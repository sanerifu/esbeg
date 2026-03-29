local markdown = require('markdown')

local args = { ... }

local input
local template

do
    local input_file = assert(io.open(args[1], "r"))
    input = assert(input_file:read("*a")) ---@type string
    input_file:close()
end

do
    local template_file = assert(io.open(args[3], "r"))
    template = assert(template_file:read("*a")) ---@type string
    template_file:close()
end

local metadata = {}

---@param s string
---@return string
local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

---@param s string
---@param delimiter string
---@return string[]
local function split(s, delimiter)
    local ret = {}
    for part in s:gmatch("([^" .. delimiter .. "]+)") do
        table.insert(ret, part)
    end
    return ret
end

local input_array = {}

for line in input:gmatch("[^\r\n]*") do
    local key, value = line:match("^%@%@%@(.-)%=(.-)$")
    if key then
        key = trim(key) ---@type string
        local splitted = split(value, ";")
        local val = {}
        for i = 1, #splitted do
            table.insert(val, trim(splitted[i]))
        end
        metadata[key] = val
    else
        if not metadata.title then
            local title = line:match("^%#([^#].*)$")
            if title then
                metadata.title = {trim(title)}
            end
        end
        table.insert(input_array, line)
    end
end

input = table.concat(input_array, '\n')

metadata.body = { markdown(input) }

local output = template:gsub("%$%@([%s%S]-)%@%$",
    ---@param expression string
    function(expression)
        local parts = split(expression, ":") ---@type {[1]: string, [2]: string?, [3]: string?}
        local before, center, after = "", "", ""
        if #parts == 1 then
            center = trim(parts[1]):gsub("%%", "%%%%")
        elseif #parts == 3 then
            before = trim(parts[1]):gsub("%%", "%%%%")
            center = trim(parts[2]):gsub("%%", "%%%%")
            after = trim(parts[3]):gsub("%%", "%%%%")
        else
            error(("Variable has %d parts. Only 1 part and 3 parts are supported"):format(#parts))
        end
        local varname = center:match("^%$(.-)%$$")
        local var = metadata[varname] or {}
        local ret = {}

        for i = 1, #var do
            local key = "%$" .. varname .. "%$"
            local value = tostring(var[i]):gsub("%%", "%%%%")
            local pushed = ("%s%s%s"):format(before, center, after)

            table.insert(ret, (pushed:gsub(key, value)))
        end

        return table.concat(ret)
    end)

do
    local output_file = assert(io.open(args[2], "w"))
    output_file:write(output)
    output_file:close()
end
