package.preload['markdown'] = function()
    local markdown = {}

    ---@type Handler
    local TextHandler

    ---@class Handler
    local Handler = {
        ---@return string start
        ---@return string closingTag
        paragraph = function()
            return "<p>", "</p>"
        end,

        ---@param str string
        ---@return string
        bold = function(str)
            return "<b>" .. str .. "</b>"
        end,

        ---@param str string
        ---@return string
        italic = function(str)
            return "<em>" .. str .. "</em>"
        end,

        ---@param level_string string
        ---@param str string
        ---@return string
        header = function(level_string, str)
            local level = #level_string
            return ("<h%d>%s</h%d>"):format(level, str, level)
        end,

        ---@param label string
        ---@param link string
        ---@return string
        inlineImage = function(label, link)
            return ("<img src=\"%s\" alt=\"%s\"/>"):format(link,
                markdown.compile(label, TextHandler):gsub("%b<>", ""):gsub("^%s*(.-)%s*$", "%1"))
        end,

        ---@param label string
        ---@param link string
        ---@return string
        blockImage = function(label, link)
            return ("<figure><img src=\"%s\" alt=\"%s\"/><figcaption>%s</figcaption></figure>"):format(link,
                markdown.compile(label, TextHandler):gsub("%b<>", ""):gsub("^%s*(.-)%s*$", "%1"), label)
        end,

        ---@param label string
        ---@param link string
        ---@return string
        link = function(label, link)
            return ("<a href=\"%s\">%s</a>"):format(link, label)
        end,

        ---@param str string
        ---@return string
        strikethrough = function(str)
            return ("<s>%s</s>"):format(str)
        end,

        ---@param code string
        ---@return string
        code = function(code)
            return "<code>" .. code .. "</code>"
        end,

        ---@param type string
        ---@param block string
        ---@return string
        codeBlock = function(type, block)
            return ("<code style=\"white-space: pre;\" type=\"%s\">%s</code>"):format(type, block)
        end,

        ---@return string start
        ---@return string closingTag
        orderedList = function()
            return "<ol>", "</ol>"
        end,

        ---@return string start
        ---@return string closingTag
        orderedListElement = function()
            return "<li>", "</li>"
        end,

        ---@return string start
        ---@return string closingTag
        unorderedList = function()
            return "<ul>", "</ul>"
        end,

        ---@return string start
        ---@return string closingTag
        unorderedListElement = function()
            return "<li>", "</li>"
        end,
    }
    Handler.__index = Handler

    TextHandler = setmetatable({
        paragraph = function() return "", "" end,
        bold = function(str) return str end,
        italic = function(str) return str end,
        header = function(level_string, str) return str end,
        inlineImage = function(label, link) return label end,
        blockImage = function(label, link) return label end,
        link = function(label, link) return label end,
        strikethrough = function(str) return str end,
        code = function(code) return code end,
        codeBlock = function(type, block) return block end,
        orderedList = function() return "", "" end,
        orderedListElement = function() return "", "" end,
    }, Handler)

    markdown.TextHandler = TextHandler
    markdown.DefaultHandler = Handler

    --- Hack. Every escaped character is encoded as their ASCII values wrapped in two 1 characters
    ---@param str string
    ---@param pattern string
    ---@param escape_character string?
    ---@return string
    local function escape(str, pattern, escape_character)
        escape_character = escape_character or '\001'
        return str:gsub(pattern, function(c) return escape_character .. tostring(string.byte(c)) .. escape_character end)
    end

    ---@class State
    ---@field tag string

    ---@param input string
    ---@param handlers Handler?
    ---@return string
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

        local ordered_list_start, ordered_list_close = handlers.orderedList()
        local ordered_list_element_start, ordered_list_element_close = handlers.unorderedListElement()
        local unordered_list_start, unordered_list_close = handlers.unorderedList()
        local unordered_list_element_start, unordered_list_element_close = handlers.unorderedListElement()
        local paragraph_start, paragraph_close = handlers.paragraph()

        local ret = {}
        local function flush()
            for i = #state, 1, -1 do
                if state[i].tag then
                    if state[i].tag == ordered_list_close then
                        table.insert(ret, ordered_list_element_close)
                    end
                    table.insert(ret, state[i].tag)
                end
                table.remove(state, #state)
            end
        end

        input = escape(
            input:
            gsub("```(.-)\n(.-)```",
                function(type, block) return ("%s"):format(escape(handler('codeBlock')(type, block), "(.)", '\002')) end)
            :
            gsub("^%s*(.+)%s*$", "%1\n\n"): -- Trim text and append empty line to denote termination
            gsub("\n\n+", "\n\n")           -- Collapse empty newlines to single one
            ,
            "\001"
        )

        for line in input:gmatch("(.-)\n") do
            local header_matches ---@type integer
            local image_matches ---@type integer
            local olist_matches ---@type integer
            local ulist_matches ---@type integer
            local code_matches ---@type integer?
            local list_indent ---@type integer?

            line = escape(line, "\\(.)")
            line, header_matches = line:gsub("^(%#+) (.*)", handler('header'))
            line, image_matches = line:gsub("^%!(%b[])(%b())$",
                function(label, link) return handler('blockImage')(label:sub(2, -2), link:sub(2, -2)) end)
            line, olist_matches = line:gsub("^(%s*)%d+%.%s*", function(indent)
                list_indent = #indent
                return ordered_list_element_start
            end)
            line, ulist_matches = line:gsub("^(%s*)%-%s+", function(indent)
                list_indent = #indent
                return unordered_list_element_start
            end)
            code_matches = line:find("^\002")
            line = line:gsub("`(.-)`", function(code) return handler('code')(escape(code, "(.)")) end)
            line = line:gsub("%!(%b[])(%b())",
                function(label, link) return handler('inlineImage')(label:sub(2, -2), link:sub(2, -2)) end)
            line = line:gsub("(%b[])(%b())",
                function(label, link) return handler('link')(label:sub(2, -2), link:sub(2, -2)) end)
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

            if #line ~= 0 then
                if header_matches ~= 0 then
                elseif image_matches ~= 0 then
                elseif olist_matches ~= 0 then
                    while #state ~= 0 and (state[#state].tag == unordered_list_close or state[#state].tag == ordered_list_close) and state[#state].indent > list_indent do
                        table.insert(ret, ordered_list_element_close)
                        table.insert(ret, state[#state].tag)
                        table.remove(state, #state)
                    end
                    if #state == 0 or ((state[#state].tag == ordered_list_close or state[#state].tag == unordered_list_close) and state[#state].indent < list_indent) then
                        table.insert(state, { tag = ordered_list_close, indent = list_indent })
                        table.insert(ret, ordered_list_start)
                    elseif (state[#state].tag == unordered_list_close or state[#state].tag == ordered_list_close) and state[#state].indent == list_indent then
                        table.insert(ret, ordered_list_element_close)
                    end
                elseif ulist_matches ~= 0 then
                    while #state ~= 0 and (state[#state].tag == unordered_list_close or state[#state].tag == ordered_list_close) and state[#state].indent > list_indent do
                        table.insert(ret, unordered_list_element_close)
                        table.insert(ret, state[#state].tag)
                        table.remove(state, #state)
                    end
                    io.stderr:write(("%q %q %q\n"):format(line, state[#state].indent, list_indent))
                    if #state == 0 or ((state[#state].tag == unordered_list_close or state[#state].tag == ordered_list_close) and state[#state].indent < list_indent) then
                        table.insert(state, { tag = unordered_list_close, indent = list_indent })
                        table.insert(ret, unordered_list_start)
                    elseif (state[#state].tag == unordered_list_close or state[#state].tag == ordered_list_close) and state[#state].indent == list_indent then
                        table.insert(ret, unordered_list_element_close)
                    end
                elseif code_matches then
                elseif #state == 0 then
                    table.insert(state, { tag = paragraph_close })
                    table.insert(ret, paragraph_start)
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
end

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

local metadata = { path = args[2] }

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

for line in input:gmatch("(.-)\n") do
    local key, value = line:match("^%@%@%@(.-)%=(.-)$")
    local title = line:match("^%#([^#].*)$")
    if key then
        key = trim(key) ---@type string
        local splitted = split(value, ";")
        local val = {}
        for i = 1, #splitted do
            table.insert(val, trim(splitted[i]))
        end
        metadata[key] = val
    elseif not metadata.title and title then
        metadata.title = { trim(title) }
    elseif title then
    else
        table.insert(input_array, (line:gsub("^%#(%#+)", "%1")))
    end
end

input = table.concat(input_array, '\n')

metadata.body = { markdown.compile(input, markdown.DefaultHandler) }

local output =
    template
    :gsub("%<%#(.-)%#%>",
        ---@param path string
        ---@return string
        function(path)
            local file = assert(io.open(trim(path), "r"))
            local data = file:read("*a")
            file:close()
            return data:gsub("%%", "%%%%")
        end)
    :gsub("%<%@%s*(.-)%s*%=%>%s*(.-)%s*%@(.-)%>",
        ---@param varname string
        ---@param expression string
        ---@param delimiter string
        ---@return string
        function(varname, expression, delimiter)
            if varname:sub(-1, -1) == '?' then
                varname = varname:sub(1, -2)
                return (metadata[varname] and #metadata[varname] > 0) and expression:gsub("%%", "%%%%") or ""
            end
            local var = metadata[varname]
            if var then
                local ret = {}
                for i = 1, #var do
                    local escaped = var[i]:gsub("%%", "%%%%")
                    local replaced = expression:gsub("%$%$", escaped)
                    table.insert(ret, replaced)
                end
                return table.concat(ret, delimiter)
            else
                return ""
            end
        end)
do
    local output_file = assert(io.open(args[2], "w"))
    output_file:write(output)
    output_file:close()
end

local EXCLUDED_FIELDS = { ['body'] = true }

local function jsonify(value)
    if type(value) == 'table' then
        local ret = {}
        if #value > 0 then
            for i = 1, #value do
                table.insert(ret, jsonify(value[i]))
            end
            return '[' .. table.concat(ret, ',') .. ']'
        else
            for k, v in pairs(value) do
                if not EXCLUDED_FIELDS[k] then
                    assert(type(k) == 'string', "Cannot jsonify non-string keys")
                    table.insert(ret, ("%q: %s"):format(k, jsonify(v)))
                end
            end
            return '{' .. table.concat(ret, ',') .. '}'
        end
    elseif type(value) == 'string' then
        return ("%q"):format(value)
    elseif type(value) == 'nil' then
        return "null"
    else
        return tostring(value)
    end
end

io.write(jsonify(metadata))
