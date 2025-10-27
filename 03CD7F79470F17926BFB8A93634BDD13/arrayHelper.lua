-- array_helpers.lua
Array = {}

-- Fügt am Ende an (push) und gibt den neuen Index zurück
function Array.push(t, v)
    local i = #t + 1
    t[i] = v
    return i
end

-- Nimmt das letzte Element (pop) und gibt es zurück (oder nil)
function Array.pop(t)
    if #t == 0 then return nil end
    local v = t[#t]
    t[#t] = nil
    return v
end

-- Fügt am Anfang ein (unshift)
function Array.unshift(t, v)
    table.insert(t, 1, v)
end

-- Nimmt das erste Element (shift) und gibt es zurück
function Array.shift(t)
    if #t == 0 then return nil end
    return table.remove(t, 1)
end

-- Entfernt an Position i (1-basiert) und gibt den entfernten Wert zurück
function Array.remove_at(t, i)
    if i < 1 or i > #t then return nil end
    return table.remove(t, i)
end

-- Sucht den ersten Index eines Werts (==), ab start (default 1). Gibt Index oder nil.
function Array.index_of(t, value, start)
    start = start or 1
    for i = start, #t do
        if t[i] == value then return i end
    end
    return nil
end

-- true, wenn value enthalten ist
function Array.contains(t, value)
    return Array.index_of(t, value) ~= nil
end

-- Entfernt die erste Vorkommnis eines Werts. Gibt true bei Erfolg.
function Array.remove_value(t, value)
    local i = Array.index_of(t, value)
    if i then
        table.remove(t, i); return true
    end
    return false
end

-- Entfernt alle Vorkommnisse eines Werts. Gibt Anzahl der Entfernungen.
function Array.remove_all(t, value)
    local n = 0
    local i = 1
    while i <= #t do
        if t[i] == value then
            table.remove(t, i)
            n = n + 1
        else
            i = i + 1
        end
    end
    return n
end

-- Kopiert (shallow)
function Array.shallow_copy(t)
    local out = {}
    for i = 1, #t do out[i] = t[i] end
    return out
end

-- Erzeugt ein „verdichtetes“ Array ohne Lücken (nützlich, wenn du nils gesetzt hast)
function Array.compact(t)
    local out, j = {}, 1
    for i = 1, math.max(#t, 1e9) do
        local v = rawget(t, i)
        if v == nil and i > #t then break end -- früh abbrechen
        if v ~= nil then out[j], j = v, j + 1 end
    end
    return out
end

-- Anzahl numerischer Elemente (zählt auch bei Lücken)
function Array.count(t)
    local n = 0
    for k, _ in pairs(t) do
        if type(k) == "number" and k >= 1 and k % 1 == 0 then n = n + 1 end
    end
    return n
end

-- Slicing: inkl. beider Grenzen (ähnlich JS). Negativ unterstützt: -1 = letztes Elem.
function Array.slice(t, i, j)
    local n = #t
    i = i or 1
    j = j or n
    if i < 0 then i = n + 1 + i end
    if j < 0 then j = n + 1 + j end
    if i < 1 then i = 1 end
    if j > n then j = n end
    local out, k = {}, 1
    for idx = i, j do out[k], k = t[idx], k + 1 end
    return out
end

-- Verkettet zwei Arrays (shallow)
function Array.concat(a, b)
    local out = Array.shallow_copy(a)
    for i = 1, #b do out[#out + 1] = b[i] end
    return out
end

-- Einzigartige Werte (stabile Reihenfolge)
function Array.unique(t)
    local seen, out = {}, {}
    for i = 1, #t do
        local v = t[i]
        if not seen[v] then
            seen[v] = true
            out[#out + 1] = v
        end
    end
    return out
end

-- map: wendet fn(v, i, t) auf jedes Element an; gibt neues Array
function Array.map(t, fn)
    local out = {}
    for i = 1, #t do out[i] = fn(t[i], i, t) end
    return out
end

-- filter: behält Elemente, für die fn(v, i, t) true liefert
function Array.filter(t, fn)
    local out = {}
    for i = 1, #t do
        local v = t[i]
        if fn(v, i, t) then out[#out + 1] = v end
    end
    return out
end

-- reduce: akkumuliert über fn(acc, v, i, t), Startwert init (oder t[1] falls nil)
function Array.reduce(t, fn, init)
    local i, acc = 1, init
    if acc == nil then
        if #t == 0 then return nil end
        acc, i = t[1], 2
    end
    for k = i, #t do acc = fn(acc, t[k], k, t) end
    return acc
end

-- chunk: teilt in Blöcke der Größe size (letzter Block ggf. kleiner)
function Array.chunk(t, size)
    assert(size >= 1, "chunk size must be >= 1")
    local out, i = {}, 1
    while i <= #t do
        out[#out + 1] = Array.slice(t, i, math.min(i + size - 1, #t))
        i = i + size
    end
    return out
end

-- flatten (flacht eine Ebene verschachtelter Arrays ab)
function Array.flatten(t)
    local out = {}
    for i = 1, #t do
        local v = t[i]
        if type(v) == "table" then
            for j = 1, #v do out[#out + 1] = v[j] end
        else
            out[#out + 1] = v
        end
    end
    return out
end

-- Dreht das Array *in-place* um (verändert t direkt)
function Array.reverse_inplace(t)
    local i, j = 1, #t
    while i < j do
        t[i], t[j] = t[j], t[i]
        i, j = i + 1, j - 1
    end
    return t
end
