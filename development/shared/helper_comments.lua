----------------------------------------------------------------
-- helper_comments.lua – Kleine Helferlein
----------------------------------------------------------------

local FileIO = require("file.FileIO")


 function drop_line_comments_stripws(text)
    local out = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local trimmed = line:match("^%s*(.*)$") or ""
        if trimmed:sub(1, 2) == "--" and trimmed:sub(1, 4) ~= "--[[" then
            -- Kommentarzeile -> weg
        else
            out[#out + 1] = line
        end
    end
    return table.concat(out, "\n")
end

-- Entfernt Kommentare aus Lua-Quelltext und wirft Leerzeilen raus.
-- Respektiert Strings ('...' / "..." / [[...]] / [=[...]=]).
function strip_lua_comments_and_blank(content)
    assert(type(content) == "string", "string expected")

    local i, n = 1, #content
    local out = {}        -- Puffer für Ausgabe
    local mode = "normal" -- "normal" | "line_comment" | "block_comment" | "str" | "lstr"
    local str_quote = nil -- ' oder "
    local lsep = ""       -- ==== bei long string/comment

    -- Matches:  --[=*[   bzw.   ]=*]
    local function long_open_at(pos)
        local eqs = content:match("^%[(=*)%[", pos)
        if eqs then return eqs end
        return nil
    end
    local function long_close_at(pos)
        local eqs = content:match("^%](=*)%]", pos)
        if eqs then return eqs end
        return nil
    end

    while i <= n do
        if mode == "normal" then
            local c = content:sub(i, i)
            local c2 = content:sub(i, i + 1)

            -- Start einer Kommentar-Sequenz?
            if c2 == "--" then
                -- Zeilen- oder Block-Kommentar?
                local eqs = long_open_at(i + 2)
                if eqs ~= nil then
                    mode = "block_comment"; lsep = eqs; i = i + 2 + 1 + #eqs -- steht auf erstem '[' der Öffnung
                else
                    mode = "line_comment"; i = i + 2
                end

                -- Long String?
            elseif c == "[" then
                local eqs = long_open_at(i)
                if eqs ~= nil then
                    mode = "lstr"; lsep = eqs
                    -- gesamten Delimiter rausgeben
                    table.insert(out, "[" .. eqs .. "[")
                    i = i + 2 + #eqs
                else
                    table.insert(out, c); i = i + 1
                end

                -- Normaler String?
            elseif c == "'" or c == '"' then
                mode = "str"; str_quote = c
                table.insert(out, c); i = i + 1
            else
                table.insert(out, c); i = i + 1
            end
        elseif mode == "line_comment" then
            -- bis Zeilenende überspringen, Newline aber behalten
            local nl1 = content:find("\n", i, true)
            if nl1 then
                table.insert(out, "\n")
                i = nl1 + 1
            else
                break -- Ende der Datei: Kommentar ignorieren, keine NL mehr
            end
        elseif mode == "block_comment" then
            -- bis passendes ]=*=] überspringen
            local eqs = long_close_at(i)
            if eqs ~= nil and eqs == lsep then
                i = i + 2 + #eqs -- nach dem schließenden ]
                mode = "normal"
            else
                i = i + 1
            end
        elseif mode == "str" then
            -- normaler String, mit Escape-Handling
            local c = content:sub(i, i)
            table.insert(out, c)
            if c == "\\" then
                -- escapen: nächstes Zeichen blind übernehmen
                local nextc = content:sub(i + 1, i + 1)
                if nextc ~= "" then
                    table.insert(out, nextc); i = i + 2
                else
                    i = i + 1
                end
            elseif c == str_quote then
                mode = "normal"; i = i + 1
            else
                i = i + 1
            end
        elseif mode == "lstr" then
            -- long string: bis passenden ]=*=]
            local eqs = long_close_at(i)
            if eqs ~= nil and eqs == lsep then
                table.insert(out, "]" .. eqs .. "]")
                i = i + 2 + #eqs
                mode = "normal"
            else
                table.insert(out, content:sub(i, i))
                i = i + 1
            end
        end
    end

    -- String zusammenbauen und Leerzeilen rauswerfen
    local text = table.concat(out)
    local cleaned = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local trimmed = line:match("^%s*(.-)%s*$") or ""
        if trimmed ~= "" then
            table.insert(cleaned, trimmed)
        end
    end
    return table.concat(cleaned, "\n")
end

-- OPTIONAL: Datei lesen & säubern, wenn du FileIO hast.
-- Falls du keine FileIO-Klasse nutzt, ersetze den Lesezugriff passend.
local function strip_lua_file(path)
    local io_ok, content = pcall(function()
        if FileIO and FileIO.new then
            local fs = FileIO.new { root = "/" }
            return fs:readAllText(path)
        else
            -- Fallback auf FN-filesystem API
            local f = filesystem.open(path, "r")
            assert(f, "cannot open file: " .. tostring(path))
            local buf, chunk = "", nil
            repeat
                chunk = f:read(64 * 1024)
                if chunk then buf = buf .. chunk end
            until not chunk
            f:close()
            return buf
        end
    end)
    if not io_ok then error("read failed: " .. tostring(content)) end
    return strip_lua_comments_and_blank(content)
end
