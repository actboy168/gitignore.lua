-- Test entry point
-- Usage: luamake lua test.lua                     (ltest only)
--        luamake lua test.lua -c                    (ltest + coverage)
--        luamake lua test.lua -g                    (ltest + git comparison)

package.path = "./?.lua;./deps/ltest/?.lua;" .. package.path

-- Parse -g flag before ltest processes args
local check_git = false
for _, arg in ipairs(arg or {}) do
    if arg == "-g" then
        check_git = true
    end
end

local lt = require "ltest"
local gitignore = require "gitignore"
local cases = require "test.cases"

-- Enable coverage for the main module
lt.moduleCoverage("gitignore")

---------------------------------------------------------------------------
-- Git comparison infrastructure
---------------------------------------------------------------------------

local tmpdir
local git_initialized = false

local function rmdir(path)
    if package.config:sub(1, 1) == "\\" then
        os.execute('rd /s /q "' .. path .. '" 2>nul')
    else
        os.execute('rm -rf "' .. path .. '"')
    end
end

local function mkdirs(path)
    if package.config:sub(1, 1) == "\\" then
        os.execute('mkdir "' .. path .. '" 2>nul')
    else
        os.execute('mkdir -p "' .. path .. '"')
    end
end

local function write_file(path, content)
    local f = io.open(path, "w")
    if f then
        f:write(content or "")
        f:close()
        return true
    end
    return false
end

local function exec(cmd)
    local handle = io.popen(cmd .. " 2>&1", "r")
    if not handle then return nil end
    local output = handle:read("*a")
    handle:close()
    return output
end

local function init_git_repo()
    if git_initialized then return end
    git_initialized = true
    if package.config:sub(1, 1) == "\\" then
        local temp = os.getenv("TEMP") or "C:\\Temp"
        tmpdir = temp .. "\\gitignore_test_" .. tostring(math.random(100000, 999999))
    else
        tmpdir = "/tmp/gitignore_test_" .. tostring(math.random(100000, 999999))
    end
    mkdirs(tmpdir)
    exec("git init " .. tmpdir)
    exec('git -C "' .. tmpdir .. '" config user.email "test@test.com"')
    exec('git -C "' .. tmpdir .. '" config user.name "test"')
end

local function git_check_ignore(patterns, path, is_dir, ignore_case)
    init_git_repo()

    -- Write .gitignore
    write_file(tmpdir .. "/.gitignore", table.concat(patterns, "\n") .. "\n")

    if ignore_case then
        exec('git -C "' .. tmpdir .. '" config core.ignoreCase true')
    else
        exec('git -C "' .. tmpdir .. '" config core.ignoreCase false')
    end

    -- Create file/directory
    local full_path = tmpdir .. "/" .. path
    local parent = full_path:match("^(.*)[/\\]")
    if parent then mkdirs(parent) end

    if is_dir then
        mkdirs(full_path)
        write_file(full_path .. "/.gitkeep", "")
    else
        write_file(full_path, "")
    end

    -- Run git check-ignore
    local git_cmd = 'git -C "' .. tmpdir .. '" check-ignore "' .. path .. '"'
    local git_output = exec(git_cmd)
    local git_ignored = (git_output ~= nil and git_output ~= "" and not git_output:find("fatal:"))

    -- Cleanup created file/directory
    if is_dir then
        rmdir(full_path)
    else
        os.remove(full_path)
    end
    os.remove(tmpdir .. "/.gitignore")

    return git_ignored
end

local function cleanup_git_repo()
    if git_initialized and tmpdir then
        rmdir(tmpdir)
    end
end

---------------------------------------------------------------------------
-- Generate ltest tests from data
---------------------------------------------------------------------------

local T = lt.test "gitignore"

for ci, tc in ipairs(cases) do
    local safe_name = tc.name:gsub("[^%w_]", "_")
    T["test_" .. ci .. "_" .. safe_name] = function(self)
        local matcher = gitignore.new(tc.patterns, { ignore_case = tc.ignore_case })

        for _, entry in ipairs(tc.paths) do
            local path = entry[1]
            local is_dir = entry[2]
            local expected = entry[3]

            local lua_result = matcher:match(path, is_dir)

            -- Assert expected result
            if expected ~= nil then
                if expected then
                    lt.assertTrue(lua_result, string.format(
                        "[%s] expected %s to be ignored", tc.name, path))
                else
                    lt.assertFalse(lua_result, string.format(
                        "[%s] expected %s to NOT be ignored", tc.name, path))
                end
            end

            -- Compare with git check-ignore
            if check_git and not tc.skip_git then
                local git_result = git_check_ignore(tc.patterns, path, is_dir, tc.ignore_case)
                lt.assertEquals(lua_result, git_result, string.format(
                    "[%s] path=%s is_dir=%s: lua=%s git=%s mismatch",
                    tc.name, path, tostring(is_dir),
                    tostring(lua_result), tostring(git_result)))
            end
        end
    end
end

-- matcher:push / matcher:pop
T["test_push_pop_basic"] = function(self)
    local matcher = gitignore.new({ "*.log" })
    lt.assertTrue(matcher:match("error.log", false))
    lt.assertFalse(matcher:match("error.txt", false))
    matcher:push({ "*.txt" })
    lt.assertTrue(matcher:match("error.txt", false))
    matcher:pop()
    lt.assertFalse(matcher:match("error.txt", false))
    lt.assertTrue(matcher:match("error.log", false))
end

T["test_push_pop_with_prefix"] = function(self)
    local matcher = gitignore.new({ "*.o" })
    matcher:push({ "!debug.o" }, "src/")
    lt.assertFalse(matcher:match("src/debug.o", false))
    lt.assertTrue(matcher:match("debug.o", false))
    matcher:pop()
    lt.assertTrue(matcher:match("src/debug.o", false))
    lt.assertTrue(matcher:match("debug.o", false))
end

T["test_push_pop_nested"] = function(self)
    local matcher = gitignore.new({ "*.tmp" })
    lt.assertTrue(matcher:match("a.tmp", false))
    lt.assertTrue(matcher:match("src/b.tmp", false))
    lt.assertTrue(matcher:match("src/core/c.tmp", false))
    -- push src/
    matcher:push({ "!keep.tmp" }, "src/")
    lt.assertFalse(matcher:match("src/keep.tmp", false))
    lt.assertTrue(matcher:match("keep.tmp", false))
    lt.assertFalse(matcher:match("src/core/keep.tmp", false))
    -- push src/core/
    matcher:push({ "keep.tmp" }, "src/core/")
    lt.assertTrue(matcher:match("src/core/keep.tmp", false))
    -- pop src/core/
    matcher:pop()
    lt.assertFalse(matcher:match("src/core/keep.tmp", false))
    -- pop src/
    matcher:pop()
    lt.assertTrue(matcher:match("src/keep.tmp", false))
    lt.assertTrue(matcher:match("a.tmp", false))
end

T["test_compile_basic"] = function(self)
    local matcher = gitignore.new({ "*.o", "!keep.o", "build/" })
    local match_fn = matcher:compile("")
    lt.assertTrue(match_fn("foo.o", "foo.o", false))
    lt.assertFalse(match_fn("keep.o", "keep.o", false))
    lt.assertFalse(match_fn("main.c", "main.c", false))
    -- 目录模式
    lt.assertTrue(match_fn("build", "build", true))
    lt.assertFalse(match_fn("build", "build", false))
end

T["test_compile_with_prefix"] = function(self)
    local matcher = gitignore.new({ "*.tmp" })
    matcher:push({ "!keep.tmp" }, "src/")
    -- compile 空 prefix（根目录）
    local match_root = matcher:compile("")
    lt.assertTrue(match_root("a.tmp", "a.tmp", false))
    lt.assertTrue(match_root("src/b.tmp", "b.tmp", false))
    -- compile src/ prefix
    local match_src = matcher:compile("src/")
    lt.assertFalse(match_src("src/keep.tmp", "keep.tmp", false))
    lt.assertTrue(match_src("src/a.tmp", "a.tmp", false))
    lt.assertTrue(match_src("keep.tmp", "keep.tmp", false))
end

T["test_compile_with_push_pop"] = function(self)
    local matcher = gitignore.new({ "*.log" })
    local fn1 = matcher:compile("")
    lt.assertTrue(fn1("error.log", "error.log", false))
    -- push 后重新 compile
    matcher:push({ "!debug.log" }, "src/")
    local fn2 = matcher:compile("src/")
    lt.assertFalse(fn2("src/debug.log", "debug.log", false))
    lt.assertTrue(fn2("src/error.log", "error.log", false))
    -- pop 后 compile 结果应还原
    matcher:pop()
    local fn3 = matcher:compile("src/")
    lt.assertTrue(fn3("src/debug.log", "debug.log", false))
end

T["test_compile_cache"] = function(self)
    local matcher = gitignore.new({ "*.o" })
    local fn1 = matcher:compile("src/")
    local fn2 = matcher:compile("src/")
    lt.assertEquals(fn1, fn2)
    -- push 后缓存应失效
    matcher:push({ "!debug.o" }, "src/")
    local fn3 = matcher:compile("src/")
    lt.assertTrue(fn1 ~= fn3)
end

T["test_edge_cases"] = function(self)
    local matcher = gitignore.new({ "*.o", "/root.o", "build/" })
    -- 空路径
    lt.assertFalse(matcher:match("", false))
    -- 路径以 / 开头（anchored 模式从根匹配，同时 unanchored 也匹配 basename）
    lt.assertTrue(matcher:match("/root.o", false))
    -- 连续 / 被规范化
    lt.assertTrue(matcher:match("build//file", false))  -- build/ 被忽略，子项也被忽略
    -- 空 push/pop
    matcher:push({}, "empty/")
    lt.assertFalse(matcher:match("empty/file", false))
    matcher:pop()
    -- pop 后行为还原
    lt.assertFalse(matcher:match("empty/file", false))
end

local exitcode = lt.run()
cleanup_git_repo()
os.exit(exitcode, true)
