local markdown = {}

---@class Handler
local Handler = {}
Handler.__index = Handler

---@param str string
---@returns string
function Handler.bold(str)
    return "<b>" .. str .. "</b>"
end

---@param str string
---@returns string
function Handler.italic(str)
    return "<em>" .. str .. "</em>"
end

---@param level_string string
---@param str string
---@returns string
function Handler.header(level_string, str)
    local level = #level_string
    return ("<h%d>%s</h%d>"):format(level, str, level)
end

---@param input string
---@param handlers Handler?
---@returns string
function markdown.compile(input, handlers)
    handlers = handlers or {}
    handlers = setmetatable(handlers, Handler)

    local state = {} ---@type string[]

    ---@param type string
    local function handler(type)
        return function(...)
            return handlers[type](...):gsub("%%", "%%%%%")
        end
    end

    local ret = {}
    input = input:
        gsub("^%s*(.+)%s*$", "%1\n\n"): -- Trim text and append empty line to denote termination
        gsub("\n\n+", "\n\n"): -- Collapse empty newlines to single one
        gsub("%z", "\0000\0") -- Encode null characters since null is used for escape

    for line in input:gmatch("(.-)\n") do
        local header_matches ---@type integer
        -- Hack. Every escaped character is encoded as their ASCII values wrapped in two null characters
        line = line:gsub("%\\(.)", function(c) return '\0' .. tostring(string.byte(c)) .. '\0' end)

        line, header_matches = line:gsub("^(%#+) (.*)", handler('header'))
        line = line:gsub("%*%*(.-)%*%*", handler('bold')):gsub("%_%_(.-)%_%_", handler('bold'))
        line = line:gsub("%*(.-)%*", handler('italic')):gsub("%_(.-)%_", handler('italic'))

        -- Decode escapes. This is safe since all null characters in the source string are encoded in this format
        -- before line processing begins
        line = line:gsub("%z(.-)%z", function(b) return string.char(tonumber(b)) end)

        if #state == 0 and #line ~= 0 then
            if header_matches ~= 0 then
            else
                table.insert(state, "p")
                table.insert(ret, "<p>")
            end
        end

        if #state > 0 and #line == 0 then
            for i=#state,1,-1 do
                table.insert(ret, ("</%s>"):format(state[i]))
                table.remove(state, #state)
            end
        end

        table.insert(ret, line)
    end

    return table.concat(ret, '\n')
end

return markdown
