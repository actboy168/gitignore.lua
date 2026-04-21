-- 性能基准测试
-- 用法: luamake lua test/bench.lua

package.path = "./?.lua;./deps/ltest/?.lua;" .. package.path

local gitignore = require "gitignore"

---------------------------------------------------------------------------
-- 基准工具
---------------------------------------------------------------------------

local function bench(name, fn, iterations)
    iterations = iterations or 100000
    -- 预热
    for _ = 1, 1000 do fn() end
    -- 计时
    local start = os.clock()
    for _ = 1, iterations do fn() end
    local elapsed = os.clock() - start
    local us_per = elapsed / iterations * 1e6
    print(string.format("%-40s %8.2f us/call  (%d iterations, %.3fs)",
        name, us_per, iterations, elapsed))
end

---------------------------------------------------------------------------
-- 创建匹配器
---------------------------------------------------------------------------

print("=== 创建匹配器 ===")
print()

-- 少量模式
bench("new(3 patterns)", function()
    gitignore.new({ "*.o", "*.a", "!keep.o" })
end)

-- 中等数量模式
local medium_patterns = {}
for i = 1, 50 do
    medium_patterns[#medium_patterns + 1] = "dir" .. i .. "/"
end
medium_patterns[#medium_patterns + 1] = "*.o"
medium_patterns[#medium_patterns + 1] = "!keep.o"

bench("new(52 patterns)", function()
    gitignore.new(medium_patterns)
end)

---------------------------------------------------------------------------
-- 匹配性能
---------------------------------------------------------------------------

print()
print("=== 匹配性能 ===")
print()

-- 简单字面量
local m1 = gitignore.new({ "*.o" })
bench("match *.o (hit)", function()
    m1:match("foo.o", false)
end)
bench("match *.o (miss)", function()
    m1:match("foo.c", false)
end)

-- 多模式
local m2 = gitignore.new(medium_patterns)
bench("match 52 patterns (hit)", function()
    m2:match("dir50/file.txt", false)
end)
bench("match 52 patterns (miss)", function()
    m2:match("other/file.txt", false)
end)

-- 通配符
local m3 = gitignore.new({ "src/**/*.c" })
bench("match src/**/*.c (hit)", function()
    m3:match("src/core/main.c", false)
end)
bench("match src/**/*.c (miss)", function()
    m3:match("lib/core/main.c", false)
end)

-- 方括号
local m4 = gitignore.new({ "[abc]*.o" })
bench("match [abc]*.o (hit)", function()
    m4:match("afoo.o", false)
end)
bench("match [abc]*.o (miss)", function()
    m4:match("xfoo.o", false)
end)

-- 取反
local m5 = gitignore.new({ "*.o", "!keep.o" })
bench("match *.o + !keep.o (negate)", function()
    m5:match("keep.o", false)
end)

-- 父目录排除
local m6 = gitignore.new({ "build/" })
bench("match build/ (parent exclude)", function()
    m6:match("build/output/app.exe", false)
end)
bench("match build/ (dir itself)", function()
    m6:match("build", true)
end)

-- 路径深度
local m7 = gitignore.new({ "a/**/b" })
bench("match a/**/b (deep path)", function()
    m7:match("a/x/y/z/w/b", false)
end)

-- 大小写不敏感
local m8 = gitignore.new({ "*.O" }, { ignore_case = true })
bench("match *.O ignore_case (hit)", function()
    m8:match("foo.o", false)
end)

-- merge (from file)
local tmpfile = os.tmpname()
local f = io.open(tmpfile, "w")
for i = 1, 100 do
    f:write("pattern" .. i .. "/\n")
end
f:write("*.o\n")
f:close()

bench("merge(101 patterns from file)", function()
    gitignore.merge({ { path = tmpfile, prefix = "" } })
end)

os.remove(tmpfile)

print()
print("=== 完成 ===")
