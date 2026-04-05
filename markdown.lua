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

---@param label string
---@param link string
---@returns string
function Handler.inlineImage(label, link)
    return ("<img src=\"%s\" alt=\"%s\"/>"):format(link, label:gsub("%b<>", ""))
end

---@param label string
---@param link string
---@returns string
function Handler.blockImage(label, link)
    return ("<figure><img src=\"%s\" alt=\"%s\"/><figcaption>%s</figcaption></figure>"):format(link, label, label)
end

---@param label string
---@param link string
---@return string
function Handler.link(label, link)
    return ("<a href=\"%s\">%s</a>"):format(link, label)
end

---@param str string
---@returns string
function Handler.strikethrough(str)
    return ("<s>%s</s>"):format(str)
end

---@param code string
---@returns string
function Handler.code(code)
    return "<code>" .. code .. "</code>"
end

---@param type string
---@param block string
---@returns string
function Handler.codeBlock(type, block)
    return ("<code style=\"white-space: pre;\" type=\"%s\">%s</code>"):format(type, block)
end

--- Hack. Every escaped character is encoded as their ASCII values wrapped in two 1 characters
---@param str string
---@param pattern string
---@param escape_character string?
---@returns string
local function escape(str, pattern, escape_character)
    escape_character = escape_character or '\001'
    return str:gsub(pattern, function(c) return escape_character .. tostring(string.byte(c)) .. escape_character end)
end

---@class State
---@field tag string

---@param input string
---@param handlers Handler?
---@returns string
function markdown.compile(input, handlers)
    handlers = handlers or {}
    handlers = setmetatable(handlers, Handler)

    local state = {} ---@type State[]

    ---@param type string
    local function handler(type)
        return function(...)
            return handlers[type](...):gsub("%%", "%%%%%")
        end
    end

    local ret = {}
    local function flush()
        for i=#state,1,-1 do
            if state[i].tag then
                table.insert(ret, ("</%s>"):format(state[i].tag))
            end
            table.remove(state, #state)
        end
    end

    input = escape(
        input:
            gsub("```(.-)\n(.-)```", function(type, block) return ("%s"):format(escape(handler('codeBlock')(type, block), "(.)", '\002')) end):
            gsub("^%s*(.+)%s*$", "%1\n\n"): -- Trim text and append empty line to denote termination
            gsub("\n\n+", "\n\n") -- Collapse empty newlines to single one
        ,
        "\001"
    )

    for line in input:gmatch("(.-)\n") do
        local header_matches ---@type integer
        local image_matches ---@type integer
        local code_matches ---@type integer?

        line = escape(line, "\\(.)")
        line, header_matches = line:gsub("^(%#+) (.*)", handler('header'))
        line, image_matches = line:gsub("^%!(%b[])(%b())$", function(label, link) return handler('blockImage')(label:sub(2, -2), link:sub(2, -2)) end)
        code_matches = line:find("^\002")
        line = line:gsub("`(.-)`", function(code) return handler('code')(escape(code, "(.)")) end)
        line = line:gsub("%!(%b[])(%b())", function(label, link) return handler('inlineImage')(label:sub(2, -2), link:sub(2, -2)) end)
        line = line:gsub("(%b[])(%b())", function(label, link) return handler('link')(label:sub(2, -2), link:sub(2, -2)) end)
        line = line:gsub("%*%*(.-)%*%*", handler('bold')):gsub("%_%_(.-)%_%_", handler('bold'))
        line = line:gsub("%*(.-)%*", handler('italic')):gsub("%_(.-)%_", handler('italic'))
        line = line:gsub("%~%~(.-)%~%~", handler('strikethrough'))

        -- Decode escapes. This is safe since all escape characters in the source string are encoded in this format
        -- before line processing begins
        line = line:gsub("\002(.-)\002", function(b) return string.char(tonumber(b)) end)
        line = line:gsub("\001(.-)\001", function(b) return string.char(tonumber(b)) end)

        if
            header_matches ~= 0 or
            image_matches ~= 0 or
            code_matches
        then
            flush()
        end

        if #state == 0 and #line ~= 0 then
            if header_matches ~= 0 then
            elseif image_matches ~= 0 then
            elseif code_matches then
            else
                table.insert(state, {tag = "p"})
                table.insert(ret, "<p>")
            end
        end

        if #state > 0 and #line == 0 then
            flush()
        end

        table.insert(ret, line)
    end

    return table.concat(ret, '\n')
end

return markdown
