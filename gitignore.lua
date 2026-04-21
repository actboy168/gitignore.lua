local m = {}

---------------------------------------------------------------------------
-- Token types
-------------------------------------------------------------------

-- { type = "literal", char = c }
-- { type = "star" }
-- { type = "doublestar" }
-- { type = "question" }
-- { type = "bracket", negated = bool, chars = {}, ranges = {} }

---------------------------------------------------------------------------
-- Tokenizer
---------------------------------------------------------------------------

local function tokenize(pattern)
    local tokens = {}
    local i = 1
    local len = #pattern

    while i <= len do
        local c = pattern:sub(i, i)

        if c == "\\" then
            -- Escape: next char is literal
            -- Note: strip_trailing_spaces guarantees no trailing backslash reaches here
            i = i + 1
            tokens[#tokens + 1] = { type = "literal", char = pattern:sub(i, i) }
            i = i + 1

        elseif c == "*" then
            -- Check for **
            if i + 1 <= len and pattern:sub(i + 1, i + 1) == "*" then
                -- Check if properly delimited
                local prev_ok = (i == 1) or (pattern:sub(i - 1, i - 1) == "/")
                local next_ok = (i + 2 > len) or (pattern:sub(i + 2, i + 2) == "/")
                if prev_ok and next_ok then
                    tokens[#tokens + 1] = { type = "doublestar" }
                    i = i + 2
                    -- Skip trailing / after ** if present (it's part of the ** construct)
                    if i <= len and pattern:sub(i, i) == "/" then
                        -- Only skip if there's more pattern after (e.g. **/foo)
                        -- For abc/**, the trailing / is kept as part of matching
                        if i + 1 <= len then
                            i = i + 1
                        end
                    end
                else
                    -- Not properly delimited: treat as two single stars
                    tokens[#tokens + 1] = { type = "star" }
                    tokens[#tokens + 1] = { type = "star" }
                    i = i + 2
                end
            else
                tokens[#tokens + 1] = { type = "star" }
                i = i + 1
            end

        elseif c == "?" then
            tokens[#tokens + 1] = { type = "question" }
            i = i + 1

        elseif c == "[" then
            -- Parse bracket expression
            local j = i + 1
            if j > len then
                -- [ at end: treat as literal
                tokens[#tokens + 1] = { type = "literal", char = "[" }
                i = i + 1
                goto continue
            end

            local negated = false
            local first = pattern:sub(j, j)
            if first == "!" or first == "^" then
                negated = true
                j = j + 1
            end

            -- ] right after [ or [!/^ is literal
            local chars = {}
            local ranges = {}
            if j <= len and pattern:sub(j, j) == "]" then
                chars["]"] = true
                j = j + 1
            end

            local found_close = false

            while j <= len do
                local ch = pattern:sub(j, j)
                if ch == "]" then
                    found_close = true
                    j = j + 1
                    break
                elseif ch == "\\" then
                    j = j + 1
                    ch = pattern:sub(j, j)
                end

                -- Check for range: a-z
                if j + 2 <= len and pattern:sub(j + 1, j + 1) == "-" and pattern:sub(j + 2, j + 2) ~= "]" then
                    local range_end = pattern:sub(j + 2, j + 2)
                    if range_end == "\\" and j + 3 <= len then
                        range_end = pattern:sub(j + 3, j + 3)
                        j = j + 4
                    else
                        j = j + 3
                    end
                    ranges[#ranges + 1] = { from = ch, to = range_end }
                else
                    chars[ch] = true
                    j = j + 1
                end
            end

            if not found_close then
                -- Unclosed bracket: treat [ as literal
                tokens[#tokens + 1] = { type = "literal", char = "[" }
                i = i + 1
            else
                tokens[#tokens + 1] = {
                    type = "bracket",
                    negated = negated,
                    chars = chars,
                    ranges = ranges,
                }
                i = j
            end

        else
            tokens[#tokens + 1] = { type = "literal", char = c }
            i = i + 1
        end

        ::continue::
    end

    return tokens
end

---------------------------------------------------------------------------
-- Pattern parser
---------------------------------------------------------------------------

local function strip_trailing_spaces(line)
    -- Strip unescaped trailing spaces
    local i = #line
    while i >= 1 do
        local c = line:sub(i, i)
        if c == " " then
            -- Check if preceded by backslash
            if i > 1 and line:sub(i - 1, i - 1) == "\\" then
                -- Escaped space: keep it, remove the backslash marker
                -- But we need to preserve the space, so stop here
                -- Remove the \ before the space
                line = line:sub(1, i - 2) .. " " .. line:sub(i + 1)
                return line
            end
            -- Unescaped trailing space: remove
            i = i - 1
        else
            break
        end
    end
    line = line:sub(1, i)

    -- Check for trailing backslash
    if #line > 0 and line:sub(#line, #line) == "\\" then
        -- Check if it's an escaped backslash \\
        local bs = 0
        local j = #line
        while j >= 1 and line:sub(j, j) == "\\" do
            bs = bs + 1
            j = j - 1
        end
        if bs % 2 == 1 then
            -- Odd number of trailing backslashes: invalid pattern
            return nil
        end
    end

    return line
end

local NEVER_MATCH = { type = "never" }

local function parse_line(line, prefix)
    -- Step 1: skip blank lines
    if line == "" or line:match("^%s*$") then
        return nil
    end

    -- Step 1b: skip comments (handle \# escape)
    if line:sub(1, 1) == "#" then
        return nil
    end
    if line:sub(1, 2) == "\\#" then
        line = "#" .. line:sub(3)
    end

    -- Step 2: handle trailing spaces
    line = strip_trailing_spaces(line)
    if line == nil then
        return NEVER_MATCH
    end

    -- Step 3: handle negation
    local negate = false
    if line:sub(1, 1) == "!" then
        negate = true
        line = line:sub(2)
    elseif line:sub(1, 2) == "\\!" then
        line = "!" .. line:sub(3)
    end

    -- Step 4: handle dir_only (trailing /)
    local dir_only = false
    if #line > 0 and line:sub(#line, #line) == "/" then
        dir_only = true
        line = line:sub(1, #line - 1)
    end

    -- Step 5: determine anchoring and strip leading /
    local anchored = false
    if line:find("/", 1, true) then
        anchored = true
        if line:sub(1, 1) == "/" then
            line = line:sub(2)
        end
    end

    -- Step 5b: apply prefix to anchored patterns
    -- For hierarchical .gitignore: anchored patterns are relative to their own directory
    if anchored and prefix and prefix ~= "" then
        line = prefix .. line
    -- Step 5c: apply prefix to unanchored patterns by converting to anchored with **/
    -- This restricts unanchored patterns to only match under the prefix directory
    elseif not anchored and prefix and prefix ~= "" then
        line = prefix .. "**/" .. line
        anchored = true
    end

    -- Step 6: tokenize (cannot return nil — strip_trailing_spaces handles trailing backslash)
    local tokens = tokenize(line)

    return {
        tokens = tokens,
        negate = negate,
        dir_only = dir_only,
        anchored = anchored,
    }
end

---------------------------------------------------------------------------
-- Glob matcher (recursive backtracking)
---------------------------------------------------------------------------

local function match_tokens(tokens, tpos, text, spos, ignore_case)
    while tpos <= #tokens do
        local tok = tokens[tpos]

        if tok.type == "literal" then
            if spos > #text then return false end
            local tc = text:sub(spos, spos)
            local pc = tok.char
            if ignore_case then
                tc = tc:lower()
                pc = pc:lower()
            end
            if tc ~= pc then return false end
            tpos = tpos + 1
            spos = spos + 1

        elseif tok.type == "question" then
            if spos > #text then return false end
            if text:sub(spos, spos) == "/" then return false end
            tpos = tpos + 1
            spos = spos + 1

        elseif tok.type == "star" then
            -- Find next literal token after * for optimization
            local next_literal = nil
            local next_tpos = tpos + 1
            while next_tpos <= #tokens do
                if tokens[next_tpos].type == "literal" then
                    next_literal = tokens[next_tpos].char
                    break
                elseif tokens[next_tpos].type == "bracket"
                    or tokens[next_tpos].type == "question" then
                    break
                end
                next_tpos = next_tpos + 1
            end

            -- Try matching 0..n characters (but not /)
            -- star can match 0 to (remaining non-/ chars), so try_pos goes up to #text+1
            local try_pos = spos
            if next_literal then
                -- Optimization: jump to first occurrence of next literal
                local search = next_literal
                if ignore_case then search = search:lower() end
                while try_pos <= #text do
                    local tc = text:sub(try_pos, try_pos)
                    if ignore_case then tc = tc:lower() end
                    if tc == search then
                        if match_tokens(tokens, tpos + 1, text, try_pos, ignore_case) then
                            return true
                        end
                    end
                    -- * cannot match /, stop at directory boundary
                    if text:sub(try_pos, try_pos) == "/" then break end
                    try_pos = try_pos + 1
                end
                -- Also try * matching nothing (spos stays)
                return match_tokens(tokens, tpos + 1, text, spos, ignore_case)
            else
                -- No optimization: try each position including #text+1 (all consumed)
                while try_pos <= #text do
                    if text:sub(try_pos, try_pos) == "/" then break end
                    if match_tokens(tokens, tpos + 1, text, try_pos, ignore_case) then
                        return true
                    end
                    try_pos = try_pos + 1
                end
                -- Try star consuming all remaining (spos = #text + 1)
                return match_tokens(tokens, tpos + 1, text, try_pos, ignore_case)
            end

        elseif tok.type == "doublestar" then
            -- ** matches zero or more path segments
            -- Try matching zero segments first, then progressively more
            if match_tokens(tokens, tpos + 1, text, spos, ignore_case) then
                return true
            end
            -- Try matching one or more characters (including /)
            local try_pos = spos
            while try_pos <= #text do
                if match_tokens(tokens, tpos + 1, text, try_pos + 1, ignore_case) then
                    return true
                end
                try_pos = try_pos + 1
            end
            return false

        elseif tok.type == "bracket" then
            if spos > #text then return false end
            local tc = text:sub(spos, spos)
            -- Bracket never matches /
            if tc == "/" then return false end

            local matched = false
            if ignore_case then tc = tc:lower() end

            if tok.chars[ignore_case and tc:lower() or tc] then
                matched = true
            elseif not matched then
                for _, r in ipairs(tok.ranges) do
                    local from, to = r.from, r.to
                    if ignore_case then
                        from = from:lower()
                        to = to:lower()
                    end
                    if tc >= from and tc <= to then
                        matched = true
                        break
                    end
                end
            end

            -- Also check original case and upper case chars if ignore_case
            if not matched and ignore_case then
                local tc_orig = text:sub(spos, spos)
                if tok.chars[tc_orig] or tok.chars[tc_orig:upper()] then
                    matched = true
                end
            end

            if tok.negated then
                matched = not matched
            end

            if not matched then return false end
            tpos = tpos + 1
            spos = spos + 1

        end
    end

    return spos > #text
end

---------------------------------------------------------------------------
-- Match function builder
---------------------------------------------------------------------------

local function build_match_fn(tokens, anchored, dir_only)
    -- 提取开头的 literal 前缀，用于快速跳过不匹配的项
    local prefix_chars = {}
    for i = 1, #tokens do
        if tokens[i].type == "literal" then
            prefix_chars[#prefix_chars + 1] = tokens[i].char
        else
            break
        end
    end
    local prefix = table.concat(prefix_chars)

    return function(path, basename, is_dir, ignore_case)
        if dir_only and not is_dir then
            return false
        end

        local text
        if anchored then
            text = path
        else
            text = basename
        end

        -- 前缀快速跳过
        if #prefix > 0 then
            if #text < #prefix then
                return false
            end
            if ignore_case then
                if text:sub(1, #prefix):lower() ~= prefix:lower() then
                    return false
                end
            else
                if text:sub(1, #prefix) ~= prefix then
                    return false
                end
            end
        end

        return match_tokens(tokens, 1, text, 1, ignore_case)
    end, prefix
end

---------------------------------------------------------------------------
-- Matcher object
---------------------------------------------------------------------------

local function evaluate_patterns(patterns, path, basename, is_dir, ignore_case, end_idx)
    -- 从后往前遍历，第一个匹配的 pattern 决定结果（gitignore 语义：后面的覆盖前面的）
    end_idx = end_idx or #patterns
    for i = end_idx, 1, -1 do
        local pat = patterns[i]
        if pat.match_fn(path, basename, is_dir, ignore_case) then
            return not pat.negate
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Tree node
---------------------------------------------------------------------------

local node_mt = {}
node_mt.__index = node_mt

function node_mt:new()
    return setmetatable({
        patterns = {},
        children = {},
    }, node_mt)
end

local matcher_mt = {}
matcher_mt.__index = matcher_mt

function matcher_mt:match(path, is_dir)
    if is_dir == nil then is_dir = false end

    -- Normalize: collapse consecutive /
    path = path:gsub("/+", "/")

    local basename = path:match("([^/]+)$") or path

    -- 收集路径上所有节点的 patterns
    local relevant = {}
    local level_ends = {}

    local node = self.root
    local level = 0
    for _, pat in ipairs(node.patterns) do
        relevant[#relevant + 1] = pat
    end
    level_ends[level] = #relevant

    local pos = 1
    while true do
        local slash = path:find("/", pos, true)
        if not slash then break end
        local name = path:sub(pos, slash - 1)
        if node then
            node = node.children[name]
        end
        level = level + 1
        if node then
            for _, pat in ipairs(node.patterns) do
                relevant[#relevant + 1] = pat
            end
        end
        level_ends[level] = #relevant
        pos = slash + 1
    end

    -- Check if any ancestor directory is excluded
    -- If so, the path is ignored regardless of negation patterns
    if path:find("/", 1, true) then
        local cache = self._parent_cache
        local ppos = 1
        local parent_level = 0
        while true do
            local slash = path:find("/", ppos, true)
            if not slash then break end
            local parent = path:sub(1, slash - 1)
            local cached = cache[parent]
            if cached == nil then
                parent_level = parent_level + 1
                local end_idx = level_ends[parent_level] or 0
                local parent_basename = parent:match("([^/]+)$") or parent
                cached = evaluate_patterns(relevant, parent, parent_basename, true, self.ignore_case, end_idx)
                cache[parent] = cached
            end
            if cached then
                return true
            end
            ppos = slash + 1
        end
    end

    return evaluate_patterns(relevant, path, basename, is_dir, self.ignore_case)
end

function matcher_mt:push(lines, prefix)
    prefix = prefix or ""

    -- 沿 prefix 走到对应节点
    local node = self.root
    if prefix ~= "" then
        for part in prefix:gmatch("([^/]+)") do
            local child = node.children[part]
            if not child then
                child = node_mt:new()
                node.children[part] = child
            end
            node = child
        end
    end

    local stack = self._push_stack
    stack[#stack + 1] = { node = node, count = #node.patterns }

    for _, line in ipairs(lines) do
        local pat = parse_line(line, prefix)
        if pat ~= nil and pat.type ~= "never" then
            pat.match_fn, pat.literal_prefix = build_match_fn(pat.tokens, pat.anchored, pat.dir_only)
            node.patterns[#node.patterns + 1] = pat
        end
    end
    self._parent_cache = {}
    self._compile_cache = {}
end

function matcher_mt:pop()
    local stack = self._push_stack
    local frame = stack[#stack]
    stack[#stack] = nil
    while #frame.node.patterns > frame.count do
        frame.node.patterns[#frame.node.patterns] = nil
    end
    self._parent_cache = {}
    self._compile_cache = {}
end

function matcher_mt:compile(prefix)
    prefix = prefix or ""

    local cache = self._compile_cache
    if not cache then
        cache = {}
        self._compile_cache = cache
    end
    local cached = cache[prefix]
    if cached then return cached end

    -- 收集到 prefix 为止的所有 patterns
    local relevant = {}
    local node = self.root
    for _, pat in ipairs(node.patterns) do
        relevant[#relevant + 1] = pat
    end

    if prefix ~= "" then
        for part in prefix:gmatch("([^/]+)") do
            node = node and node.children[part]
            if node then
                for _, pat in ipairs(node.patterns) do
                    relevant[#relevant + 1] = pat
                end
            end
        end
    end

    -- 按 literal_prefix 进一步过滤：只保留与当前 prefix 可能相关的 anchored patterns
    local filtered = {}
    for _, pat in ipairs(relevant) do
        if not pat.anchored then
            filtered[#filtered + 1] = pat
        else
            local lp = pat.literal_prefix or ""
            if #lp == 0
                or lp:sub(1, #prefix) == prefix
                or prefix:sub(1, #lp) == lp
            then
                filtered[#filtered + 1] = pat
            end
        end
    end

    local ignore_case = self.ignore_case
    local match_fn = function(path, basename, is_dir)
        for i = #filtered, 1, -1 do
            local pat = filtered[i]
            if pat.match_fn(path, basename, is_dir, ignore_case) then
                return not pat.negate
            end
        end
        return false
    end
    cache[prefix] = match_fn
    return match_fn
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function m.new(patterns, opts)
    opts = opts or {}
    local self = setmetatable({
        root = node_mt:new(),
        ignore_case = opts.ignore_case or false,
        _parent_cache = {},
        _push_stack = {},
    }, matcher_mt)

    self:push(patterns, "")
    return self
end

---------------------------------------------------------------------------
-- Hierarchical .gitignore merging
---------------------------------------------------------------------------

local function count_slashes(s)
    local n = 0
    for _ in s:gmatch("/") do n = n + 1 end
    return n
end

function m.merge(entries, opts)
    opts = opts or {}

    -- Sort by prefix depth (shallow first = lower priority, deep last = higher priority)
    local sorted = {}
    for i, entry in ipairs(entries) do
        sorted[i] = entry
    end
    table.sort(sorted, function(a, b)
        return count_slashes(a.prefix or "") < count_slashes(b.prefix or "")
    end)

    local self = m.new({}, opts)

    for _, entry in ipairs(sorted) do
        local prefix = entry.prefix or ""
        local lines = entry.patterns or {}

        -- Load from file if path specified
        if entry.path then
            local f = io.open(entry.path, "r")
            if f then
                local file_lines = {}
                for line in f:lines() do
                    file_lines[#file_lines + 1] = line
                end
                f:close()
                -- Merge file lines with explicit patterns (file first, then explicit)
                for _, l in ipairs(lines) do
                    file_lines[#file_lines + 1] = l
                end
                lines = file_lines
            end
        end

        self:push(lines, prefix)
    end

    return self
end

return m
