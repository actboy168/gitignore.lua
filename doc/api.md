# gitignore.lua API 文档

## 概述

`gitignore.lua` 是一个符合 git 完整规范的 `.gitignore` 模式匹配 Lua 库。支持 gitignore 的所有特性，包括通配符、双星号、方括号表达式、取反、目录模式、锚定模式和反斜杠转义。

## 引入

```lua
local gitignore = require "gitignore"
```

## API

### gitignore.new(patterns, opts)

从模式列表创建匹配器。

**参数：**

- `patterns` (`table`): `.gitignore` 模式字符串列表，每条规则与 `.gitignore` 文件中的行格式一致
- `opts` (`table|nil`): 选项表
  - `opts.ignore_case` (`boolean`): 是否忽略大小写，默认 `false`

**返回：**

- 匹配器对象 (`matcher`)

**示例：**

```lua
local matcher = gitignore.new({
    "*.o",
    "!keep.o",
    "build/",
})

local matcher_ci = gitignore.new({ "Foo" }, { ignore_case = true })
```

### gitignore.merge(entries, opts)

从多层 `.gitignore` 创建匹配器，支持层级优先级。与 git 的行为一致：更深层目录的 `.gitignore` 优先级更高。

**参数：**

- `entries` (`table`): 层级条目列表，每个条目为包含以下字段的表：
  - `patterns` (`table|nil`): 模式字符串列表
  - `path` (`string|nil`): `.gitignore` 文件路径（可与 `patterns` 同时使用，文件内容在前）
  - `prefix` (`string`): 该 `.gitignore` 相对于仓库根目录的路径前缀（如 `"src/"`），根目录用 `""`
- `opts` (`table|nil`): 选项表，同 `gitignore.new`

**返回：**

- 匹配器对象 (`matcher`)

**优先级规则：**

- 条目按 `prefix` 深度自动排序（浅的在前 = 低优先级，深的在后 = 高优先级）
- 锚定模式（含 `/`）自动加上 `prefix` 前缀，使其相对于自身目录
- 非锚定模式自动转换为 `prefix + "**/" + pattern`，限制在该目录树下生效

**示例：**

```lua
-- 模拟 git 多层 .gitignore
local matcher = gitignore.merge({
    { patterns = { "*.o", "build/" }, prefix = "" },           -- 根目录
    { patterns = { "!debug.o" }, prefix = "src/" },            -- src/ 目录
    { path = "src/core/.gitignore", prefix = "src/core/" },    -- src/core/ 目录
})

matcher:match("foo.o", false)             -- true  （根目录 *.o）
matcher:match("src/debug.o", false)       -- false （src/ 的 !debug.o 取反）
matcher:match("src/build", true)          -- true  （根目录 build/）
```

### matcher:match(path, is_dir)

判断路径是否被忽略。

**参数：**

- `path` (`string`): 文件或目录路径，使用 `/` 作为分隔符（连续的 `/` 会被自动规范化）
- `is_dir` (`boolean|nil`): 路径是否为目录，默认 `false`

**返回：**

- (`boolean`): `true` 表示被忽略，`false` 表示不被忽略

**示例：**

```lua
local matcher = gitignore.new({ "*.o", "!keep.o", "build/" })

matcher:match("foo.o", false)        -- true  （匹配 *.o）
matcher:match("keep.o", false)       -- false （取反 !keep.o）
matcher:match("build", true)         -- true  （匹配 build/）
matcher:match("build", false)        -- false （build/ 只匹配目录）
matcher:match("build/output", false) -- true  （父目录 build 被排除）
matcher:match("src/main.c", false)   -- false （不匹配任何规则）
```

### matcher:push(lines, prefix) / matcher:pop()

动态追加和还原规则，用于遍历目录树时按需加载子目录的 `.gitignore`。`push` 和 `pop` 必须配对使用（栈式）。

**参数（push）：**

- `lines` (`table`): `.gitignore` 模式字符串列表
- `prefix` (`string|nil`): 路径前缀，同 `gitignore.merge` 中的 `prefix` 字段，默认 `""`

**示例：**

```lua
local matcher = gitignore.new({ "*.o" })
matcher:match("src/debug.o", false)   -- true

-- 进入 src/ 目录，追加该目录的 .gitignore 规则
matcher:push({ "!debug.o" }, "src/")
matcher:match("src/debug.o", false)   -- false（src/ 下的取反生效）
matcher:match("debug.o", false)       -- true （根目录下仍被忽略）

-- 离开 src/ 目录，还原规则
matcher:pop()
matcher:match("src/debug.o", false)   -- true（还原后取反规则不再生效）
```

## 匹配规则

详细规则说明见 [doc/spec.md](spec.md)。以下为简要总结：

| 特性 | 语法 | 说明 |
|------|------|------|
| 注释 | `# comment` | 以 `#` 开头的行被忽略 |
| 取反 | `!pattern` | 重新包含已被排除的文件 |
| 目录模式 | `pattern/` | 只匹配目录 |
| 锚定 | `/pattern` 或 `a/b` | 含 `/` 的模式从仓库根目录匹配 |
| 通配符 | `*` | 匹配除 `/` 外的任意字符 |
| 单字符 | `?` | 匹配除 `/` 外的单个字符 |
| 方括号 | `[abc]` `[a-z]` | 匹配方括号内的字符 |
| 双星号 | `**` | 匹配零个或多个目录层级 |
| 转义 | `\*` | 反斜杠转义特殊字符 |
| 父目录排除 | — | 父目录被排除时，取反模式无法重新包含其子项 |

## 选项

### ignore_case

```lua
local matcher = gitignore.new({ "Foo" }, { ignore_case = true })

matcher:match("Foo", false)  -- true
matcher:match("foo", false)  -- true
matcher:match("FOO", false)  -- true
```

启用后，所有模式匹配忽略大小写，包括字面量、通配符优化和方括号表达式。

## 注意事项

- 路径使用 `/` 作为分隔符，不使用 `\`
- 父目录被排除后，取反模式无法重新包含其子项（与 git 行为一致）
- 无效模式（如末尾反斜杠 `foo\`）被静默忽略
- `is_dir` 参数影响目录模式（`pattern/`）的匹配结果
