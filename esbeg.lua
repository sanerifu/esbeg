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
                metadata.title = { trim(title) }
            end
        end
        table.insert(input_array, line)
    end
end

input = table.concat(input_array, '\n')

metadata.body = { markdown(input) }

local output = template:gsub("%<%$%s*(.-)%s*%=%>%s*(.-)%s*%$%>",
    ---@param varname string
    ---@param expression string
    function(varname, expression)
        local var = metadata[varname]
        if var then
            local ret = {}
            for i = 1, #var do
                local escaped = var[i]:gsub("%%", "%%%%")
                local replaced = expression:gsub("%@%@", escaped)
                table.insert(ret, replaced)
            end
            return table.concat(ret)
        else
            return ""
        end
    end)
do
    local output_file = assert(io.open(args[2], "w"))
    output_file:write(output)
    output_file:close()
end
