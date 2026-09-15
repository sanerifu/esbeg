package.preload['markdown'] = function()
    local markdown = {}

    ---@param s string
    ---@return string
    local function trim(s)
        return s:match("^%s*(.-)%s*$")
    end

    --- Hack. Every escaped character is encoded as their ASCII values wrapped in two 1 characters
    ---@param str string
    ---@param pattern string
    ---@param escape_character string?
    ---@return string
    local function escape(str, pattern, escape_character)
        escape_character = escape_character or '\001'
        return (str:gsub(pattern, function(c) return escape_character .. tostring(string.byte(c)) .. escape_character end))
    end

    local char_map = {
        ['ç'] = 'ch',
        ['Ç'] = 'Ch',
        ['ğ'] = 'g',
        ['Ğ'] = 'G',
        ['ı'] = 'i',
        ['İ'] = 'I',
        ['ö'] = 'o',
        ['Ö'] = 'O',
        ['ü'] = 'u',
        ['Ü'] = 'U',
        ['ş'] = 'sh',
        ['Ş'] = 'Sh',
        [' '] = '-',
    }

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
            local id = trim(markdown.compile(str, TextHandler))
                :gsub("[\1-\127\194-\244][\128-\191]*", char_map)
                :lower()

            local level = #level_string
            return ("<h%d id=\"%s\">%s <a aria-hidden=\"true\" style=\"display: inline-block;\" href=\"#%s\">§</a></h%d>")
                :format(level, id, str, id, level)
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
            return "<code class=\"inline-code\">" .. code .. "</code>"
        end,

        ---@param type string
        ---@param block string
        ---@return string
        codeBlock = function(type, block)
            return ("<code class=\"block-code\" type=\"%s\">%s</code>"):format(type, block)
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
        unorderedList = function() return "", "" end,
        unorderedListElement = function() return "", "" end,
    }, Handler)

    markdown.TextHandler = TextHandler
    markdown.DefaultHandler = Handler

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
                return handlers[type](...):gsub("%%", "%%%%")
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
                function(type, block)
                    return ("%s"):format(escape(
                        handler('codeBlock')(type, block:gsub("%<", "&lt;"):gsub("%>", "&gt;")), "(.)", '\002'))
                end)
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
            line = line:gsub("`(.-)`",
                function(code) return handler('code')(escape(code:gsub("%<", "&lt;"):gsub("%>", "&gt;"), "(.)")) end)
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

---@param path string
---@return string content
local function readFile(path)
    local file = assert(io.open(path, "r"))
    local content = assert(file:read("*a")) ---@type string
    file:close()
    return content
end

---@param path string
---@param content string?
local function writeFile(path, content)
    if content == nil then
        return
    end
    local file = assert(io.open(path, "w"))
    assert(file:write(content))
    file:close()
end

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

local loader = loadstring or load
---@param expr string
---@param env table
---@param ... any
local function eval(expr, env, ...)
    local chunk = assert(loader("return " .. expr, "=eval"))
    if setfenv then
        setfenv(chunk, env)
    else
        debug.setupvalue(chunk, 1, env)
    end
    local ret = chunk(...)
    return ret
end

local function metadataToHtml(template, metadata, metadata_context, root)
    return
        template
        :gsub("%<include%s+path%s*%=%s*%\"(.-)%\"%s*%/?%>",
            ---@param path string
            ---@return string
            function(path)
                local file = assert(io.open(root .. trim(path), "r"))
                local data = file:read("*a")
                file:close()
                return data:gsub("%%", "%%%%")
            end)
        :gsub("%<if%s+expression%s*%=%s*%\"(.-)%\"%s*%>(.-)%<%/if%>",
            ---@param expression string
            ---@param body string
            function(expression, body)
                return (eval(expression, metadata_context) and body or ""):gsub("%%", "%%%%")
            end)
        :gsub(
            "%<replace%s+variable%s*%=%s*%\"(.-)%\"%s+placeholder%s*%=%s*%\"(.-)%\"(%s+delimiter%s*%=%s*%\"(.-)%\")%s*%>(.-)%<%/replace%>",
            ---@param variable string
            ---@param placeholder string
            ---@param delimiter string
            ---@param body string
            function(variable, placeholder, _, delimiter, body)
                local value = metadata[variable]
                if not value then
                    return ""
                end

                local ret = {}
                for i = 1, #value do
                    local escaped = value[i]:gsub("%%", "%%%%")
                    local replaced = body:gsub(placeholder, escaped)
                    table.insert(ret, replaced)
                end
                ret = table.concat(ret, (delimiter:gsub("%%", "%%%%")))
                return ret
            end)
end

local function metadataToIndex(metadata)
    if metadata.title == nil or #metadata.title < 1 then
        return nil
    end
    return ([[            <li>
                <a href="/%s" style="display: block;">%s</a>
                <div>Tarih: %s</div>
                <div>Yazan%s: %s</div>
                <div>Etiketler: %s</div>
            </li>

]]):format(
        metadata.path, metadata.title[1],
        metadata.date and metadata.date[1] or "",
        (metadata.authors and #metadata.authors > 1) and "lar" or "",
        metadata.authors and table.concat(metadata.authors, "; "),
        metadata.tags and table.concat(metadata.tags, "; ")
    )
end

local function metadataToRss(metadata)
    if metadata.title == nil or #metadata.title < 1 then
        return nil
    end
    local weekday_mapping = {
        ["Pzt"] = "Mon",
        ["Sal"] = "Tue",
        ["Çrş"] = "Wed",
        ["Prş"] = "Thu",
        ["Cum"] = "Fri",
        ["Cmt"] = "Sat",
        ["Paz"] = "Sun",
    }

    local month_mapping = {
        ["01"] = "Jan",
        ["02"] = "Feb",
        ["03"] = "Mar",
        ["04"] = "Apr",
        ["05"] = "May",
        ["06"] = "Jun",
        ["07"] = "Jul",
        ["08"] = "Aug",
        ["09"] = "Sep",
        ["10"] = "Oct",
        ["11"] = "Nov",
        ["12"] = "Dec",
    }

    ---@param extendedIso string?
    ---@return string?
    local function makeRfc2822(extendedIso)
        if not extendedIso then
            return nil
        end
        local year, month, day, hour, minute, second, timezone, weekday = extendedIso:match(
            "^(....)%-(..)%-(..) (..):(..):(..) (.....) (.+)$"
        )

        return ("%s, %d %s %d %s:%s:%s %s"):format(
            weekday_mapping[weekday],
            tonumber(day),
            month_mapping[month],
            tonumber(year),
            hour,
            minute,
            second,
            timezone
        )
    end

    ---@param tag string
    ---@param text string?
    ---@return string
    local function wrapInTags(tag, text)
        if text then
            return ("<%s>%s</%s>"):format(tag, text, tag)
        else
            return ""
        end
    end

    ---@param text string
    ---@param start integer
    ---@param finish integer
    ---@return string
    local function utf8Slice(text, start, finish)
        local t = {}
        local i = 1
        for c in text:gmatch("[\1-\127\194-\244][\128-\191]*") do
            if start <= i and i <= finish then
                table.insert(t, c)
            end
            i = i + 1
        end
        return table.concat(t, "")
    end

    return (
        "    <item>\n" ..
        "        %s\n" ..
        "        %s\n" ..
        "        %s\n" ..
        "        %s\n" ..
        "    </item>\n\n"
    ):format(
        wrapInTags("title", metadata.title and metadata.title[1] or nil),
        wrapInTags("description",
            metadata.plaintext[1] and (utf8Slice(metadata.plaintext[1], 1, 120) .. "...") or nil),
        wrapInTags("link", metadata.path and ("https://sanerifu.github.io/" .. metadata.path) or nil),
        wrapInTags("pubDate", makeRfc2822(metadata.date and metadata.date[1] or nil))
    )
end

local commands = {
    compile = function()
        local output = {
            html = args[1], ---@type string
            index = args[2], ---@type string
            rss = args[3], ---@type string
        }
        local input = {
            markdown = readFile(args[4]),
            template = readFile(args[5]),
            root = args[6],
        }

        local metadata = { path = output.html:match("(.+)%/index.html"):gsub(input.root, "") }

        local input_array = {}

        for line in input.markdown:gmatch("(.-)\n") do
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
                metadata.page_title = { trim(title) }
            elseif title then
            else
                table.insert(input_array, (line:gsub("^%#(%#+)", "%1")))
            end
        end

        input.markdown = table.concat(input_array, '\n')

        metadata.body = { markdown.compile(input.markdown, markdown.DefaultHandler) }
        metadata.plaintext = { markdown.compile(input.markdown, markdown.TextHandler) }

        local metadata_context = {} ---@type table<string, boolean | integer>
        for k in pairs(metadata) do
            metadata_context[k] = #metadata[k] > 0
            metadata_context[k .. '_count'] = #metadata[k]
        end

        writeFile(output.html, metadataToHtml(input.template, metadata, metadata_context, input.root))
        writeFile(output.index, metadataToIndex(metadata))
        writeFile(output.rss, metadataToRss(metadata))
    end,

    replace = function()
        local output = {
            merged = table.remove(args, 1),
        }
        local input = {
            template = table.remove(args, 1),
            files = args,
        }

        local content = {}
        for i = 1, #input.files do
            table.insert(content, readFile(input.files[i]))
        end
        writeFile(
            output.merged,
            readFile(input.template):gsub("%@DATA%@", table.concat(content, "")):gsub("%@COUNT%@", tostring(#content))
        )
    end,
}

local command = table.remove(args, 1)
commands[command]()
