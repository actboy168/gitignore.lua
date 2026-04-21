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
    if package.config:sub(1,1) == "\\" then
        os.execute('rd /s /q "' .. path .. '" 2>nul')
    else
        os.execute('rm -rf "' .. path .. '"')
    end
end

local function mkdirs(path)
    if package.config:sub(1,1) == "\\" then
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
    if package.config:sub(1,1) == "\\" then
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

---------------------------------------------------------------------------
-- Hierarchical .gitignore merge tests
---------------------------------------------------------------------------

-- Basic hierarchy: root excludes *.o, subdirectory re-includes debug.o
T["test_merge_basic"] = function(self)
    local matcher = gitignore.merge({
        { patterns = { "*.o" }, prefix = "" },
        { patterns = { "!debug.o" }, prefix = "src/" },
    })
    lt.assertTrue(matcher:match("foo.o", false))
    lt.assertTrue(matcher:match("src/foo.o", false))
    lt.assertFalse(matcher:match("src/debug.o", false))
end

-- Anchored pattern with prefix: /foo in subdirectory only matches under that subdir
T["test_merge_anchored_prefix"] = function(self)
    local matcher = gitignore.merge({
        { patterns = { "/foo" }, prefix = "" },
        { patterns = { "/bar" }, prefix = "src/" },
    })
    -- Root /foo matches foo at root only
    lt.assertTrue(matcher:match("foo", false))
    lt.assertFalse(matcher:match("a/foo", false))
    -- src/'s /bar becomes src/bar — matches src/bar only
    lt.assertTrue(matcher:match("src/bar", false))
    lt.assertFalse(matcher:match("bar", false))
    lt.assertFalse(matcher:match("other/bar", false))
end

-- Depth sorting: deeper .gitignore overrides parent
T["test_merge_depth_priority"] = function(self)
    local matcher = gitignore.merge({
        { patterns = { "*.log" }, prefix = "src/" },
        { patterns = { "!important.log" }, prefix = "" },
    })
    -- Entry with prefix="" has 0 slashes, prefix="src/" has 1
    -- So "" is lower priority (first), "src/" is higher priority (last)
    -- *.log from src/ overrides !important.log from root
    lt.assertTrue(matcher:match("src/important.log", false))
    lt.assertTrue(matcher:match("src/other.log", false))
end

-- Three levels of hierarchy
T["test_merge_three_levels"] = function(self)
    local matcher = gitignore.merge({
        { patterns = { "*.tmp" }, prefix = "" },
        { patterns = { "!keep.tmp" }, prefix = "src/" },
        { patterns = { "keep.tmp" }, prefix = "src/core/" },
    })
    lt.assertTrue(matcher:match("foo.tmp", false))
    lt.assertFalse(matcher:match("src/keep.tmp", false))
    lt.assertTrue(matcher:match("src/core/keep.tmp", false))
end

-- Unanchored patterns with prefix are scoped to that directory tree
T["test_merge_unanchored_with_prefix"] = function(self)
    local matcher = gitignore.merge({
        { patterns = { "*.o" }, prefix = "src/" },
    })
    -- *.o with prefix="src/" becomes src/**/*.o — only matches under src/
    lt.assertFalse(matcher:match("foo.o", false))
    lt.assertTrue(matcher:match("src/foo.o", false))
    lt.assertTrue(matcher:match("src/sub/foo.o", false))
    lt.assertFalse(matcher:match("other/foo.o", false))
end

-- Dir pattern with prefix
T["test_merge_dir_pattern_prefix"] = function(self)
    local matcher = gitignore.merge({
        { patterns = { "build/" }, prefix = "src/" },
    })
    -- build/ with prefix="src/" only matches under src/
    lt.assertFalse(matcher:match("build", true))
    lt.assertTrue(matcher:match("src/build", true))
    lt.assertTrue(matcher:match("src/sub/build", true))
    -- With anchored dir: /output/ with prefix src/
    local matcher2 = gitignore.merge({
        { patterns = { "/output/" }, prefix = "src/" },
    })
    lt.assertFalse(matcher2:match("output", true))
    lt.assertTrue(matcher2:match("src/output", true))
end

-- m.merge with path loading
T["test_merge_with_path"] = function(self)
    local tmpfile = os.tmpname()
    write_file(tmpfile, "*.log\n!important.log\n")
    local matcher = gitignore.merge({
        { patterns = { "*.tmp" }, prefix = "" },
        { path = tmpfile, prefix = "src/" },
    })
    lt.assertTrue(matcher:match("foo.tmp", false))
    lt.assertTrue(matcher:match("src/debug.log", false))
    lt.assertFalse(matcher:match("src/important.log", false))
    os.remove(tmpfile)
end

-- m.merge with both path and patterns in same entry
T["test_merge_path_and_patterns"] = function(self)
    local tmpfile = os.tmpname()
    write_file(tmpfile, "*.log\n")
    local matcher = gitignore.merge({
        { path = tmpfile, patterns = { "!keep.log" }, prefix = "src/" },
    })
    lt.assertTrue(matcher:match("src/debug.log", false))
    lt.assertFalse(matcher:match("src/keep.log", false))
    os.remove(tmpfile)
end

-- m.merge with empty prefix (same as m.new)
T["test_merge_empty_prefix"] = function(self)
    local matcher = gitignore.merge({
        { patterns = { "*.o", "!keep.o" }, prefix = "" },
    })
    lt.assertTrue(matcher:match("foo.o", false))
    lt.assertFalse(matcher:match("keep.o", false))
end

-- Cleanup on exit
local orig_exit = os.exit
os.exit = function(code, close)
    cleanup_git_repo()
    orig_exit(code, close)
end

os.exit(lt.run(), true)
