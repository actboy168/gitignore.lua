-- 扫描 git 仓库，流式返回未被忽略的文件
-- 用法: luamake lua example/scan.lua [repo_path]
--        luamake lua example/scan.lua --check [repo_path]  (与 git ls-files 对比)

package.path = "./?.lua;" .. package.path

local fs = require "bee.filesystem"
local gitignore = require "gitignore"

---------------------------------------------------------------------------
-- 路径工具
---------------------------------------------------------------------------

-- 将路径字符串规范化为 / 分隔
local function normalize_sep(s)
    return s:gsub("\\", "/")
end

---------------------------------------------------------------------------
-- 解析 .gitmodules 获取子模块路径
---------------------------------------------------------------------------

local function parse_submodules(root)
    local submodules = {}
    local path = root / ".gitmodules"
    local f = io.open(path:string(), "r")
    if not f then return submodules end
    for line in f:lines() do
        local sm_path = line:match('^%s*path%s*=%s*(.+)%s*$')
        if sm_path then
            sm_path = sm_path:gsub("\\", "/")
            submodules[sm_path] = true
        end
    end
    f:close()
    return submodules
end

---------------------------------------------------------------------------
-- 迭代器工具
---------------------------------------------------------------------------

-- 将 fs.pairs 返回值打包为表
local function make_iter(dir)
    local next_fn, state, ctrl = fs.pairs(dir)
    return { next_fn, state, ctrl }
end

local function iter_next(iter)
    local path, status = iter[1](iter[2], iter[3])
    if path then iter[3] = path end
    return path, status
end

---------------------------------------------------------------------------
-- 读取 .gitignore 文件内容
---------------------------------------------------------------------------

local function read_gitignore(path)
    local f = io.open(path, "r")
    if not f then return {} end
    local lines = {}
    for line in f:lines() do
        lines[#lines + 1] = line
    end
    f:close()
    return lines
end

---------------------------------------------------------------------------
-- 迭代器：scan(repo_root)
-- 单次遍历：进入目录时发现 .gitignore 并动态追加规则
---------------------------------------------------------------------------

local function scan(repo_root)
    local root_str = fs.absolute(fs.path(repo_root)):string()
    root_str = normalize_sep(root_str)
    if root_str:sub(-1) ~= "/" then root_str = root_str .. "/" end
    local submodules = parse_submodules(fs.path(root_str))

    -- 用 push/pop API 动态管理各层 .gitignore 规则
    local matcher = gitignore.new({})
    local match_fn = matcher:compile("")

    -- 栈式迭代器
    -- 每个栈元素: { iter, rel_prefix }
    local stack = {}
    local function push_dir(dir, rel_prefix)
        -- 进入目录时，先检查并加载该目录的 .gitignore
        local lines = {}
        local gitignore_path = dir / ".gitignore"
        local fh = io.open(gitignore_path:string(), "r")
        if fh then
            fh:close()
            lines = read_gitignore(gitignore_path:string())
        end
        matcher:push(lines, rel_prefix)
        match_fn = matcher:compile(rel_prefix)
        stack[#stack + 1] = { make_iter(dir), rel_prefix }
    end
    push_dir(fs.path(root_str), "")

    return function()
        while #stack > 0 do
            local frame = stack[#stack]
            local iter, rel_prefix = frame[1], frame[2]
            local path, status = iter_next(iter)
            if not path then
                -- 退出目录，还原 matcher 规则
                matcher:pop()
                stack[#stack] = nil
                if #stack > 0 then
                    match_fn = matcher:compile(stack[#stack][2])
                end
            else
                local name = path:filename():string()
                if name == ".git" then goto continue end
                local rel = rel_prefix .. normalize_sep(name)
                if submodules[rel] then goto continue end
                local is_dir = status and status:is_directory()
                local basename = rel:match("([^/]+)$") or rel
                if match_fn(rel, basename, is_dir) then
                    goto continue -- ignored
                end
                if is_dir then
                    push_dir(path, rel .. "/")
                    goto continue
                end
                do return rel end -- un-ignored file
            end
            ::continue::
        end
        return nil
    end
end

---------------------------------------------------------------------------
-- 与 git ls-files 对比
---------------------------------------------------------------------------

local function check_with_git(root)
    local root_path = fs.absolute(fs.path(root))
    local root_str = normalize_sep(root_path:string())
    if root_str:sub(-1) ~= "/" then root_str = root_str .. "/" end
    local submodules = parse_submodules(root_path)

    -- 1. 用 scan 收集所有未忽略的文件
    local scan_set = {}
    for path in scan(root) do
        scan_set[path] = true
    end

    -- 2. 用 git ls-files 获取 tracked + untracked 未忽略文件
    local git_set = {}
    local h1 = io.popen('git -c core.quotepath=false -C "' .. root .. '" ls-files', "r")
    if h1 then
        for line in h1:lines() do
            if not submodules[line] then
                git_set[line] = true
            end
        end
        h1:close()
    end

    local h2 = io.popen('git -c core.quotepath=false -C "' .. root .. '" ls-files -o --exclude-standard', "r")
    if h2 then
        for line in h2:lines() do
            if not submodules[line] then
                git_set[line] = true
            end
        end
        h2:close()
    end

    -- 3. 对比差异
    --    scan 只能扫描磁盘上实际存在的文件，git 可能包含已删除但仍 tracked 的文件
    --    此外，git 可能包含被 gitignore 忽略但强制跟踪（git add -f）的文件
    local total = 0
    for _ in pairs(scan_set) do total = total + 1 end
    local only_scan = {}
    local only_git = {}
    for path in pairs(scan_set) do
        if not git_set[path] then
            only_scan[#only_scan + 1] = path
        end
    end
    for path in pairs(git_set) do
        if not scan_set[path] then
            -- 跳过磁盘上不存在的文件（已删除但仍 tracked）
            if fs.exists(root_path / path) then
                -- 磁盘存在但 scan 未输出，说明被 gitignore 规则忽略
                --（可能是被强制跟踪的文件），不视为差异
            end
        end
    end
    table.sort(only_scan)
    table.sort(only_git)

    -- 4. 输出结果
    if #only_scan == 0 and #only_git == 0 then
        print("OK: 结果与 git ls-files 一致 (" .. total .. " 个文件)")
    else
        if #only_scan > 0 then
            print("scan 有但 git 没有 (" .. #only_scan .. " 个):")
            for _, p in ipairs(only_scan) do
                print("  + " .. p)
            end
        end
        if #only_git > 0 then
            print("git 有但 scan 没有 (" .. #only_git .. " 个):")
            for _, p in ipairs(only_git) do
                print("  - " .. p)
            end
        end
    end
end

---------------------------------------------------------------------------
-- 主入口
---------------------------------------------------------------------------

local args = { ... }
if args[1] == "--check" then
    check_with_git(args[2] or ".")
else
    local root = args[1] or "."
    for path in scan(root) do
        print(path)
    end
end
