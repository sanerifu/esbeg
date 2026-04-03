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

    local state = nil ---@type string?

    ---@param type string
    local function handler(type)
        return function(...)
            return handlers[type](...):gsub("%%", "%%%%%")
        end
    end

    local ret = {}

    for line in input:gsub("^%s*(.+)%s*$", "%1"):gsub("\n\n+", "\n"):gmatch("[^\n]*") do
        local header_matches ---@type integer
        line = line:gsub("%\\(.)", function(c) return '\0' .. tostring(string.byte(c)) .. '\0' end)
        line, header_matches = line:gsub("^(%#+) (.*)", handler('header'))
        line = line:gsub("%*%*(.-)%*%*", handler('bold')):gsub("%_%_(.-)%_%_", handler('bold'))
        line = line:gsub("%*(.-)%*", handler('italic')):gsub("%_(.-)%_", handler('italic'))
        line = line:gsub("%z(.-)%z", function(b) return string.char(tonumber(b)) end)

        if state == nil and #line ~= 0 then
            if header_matches ~= 0 then
            else
                state = "p"
                table.insert(ret, "<p>")
            end
        end

        if state ~= nil and #line == 0 then
            table.insert(ret, ("</%s>"):format(state))
            state = nil
        end

        table.insert(ret, line)
    end

    return table.concat(ret, '\n')
end

return markdown
