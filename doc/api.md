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
- `prefix` (`string|nil`): 路径前缀，表示该 `.gitignore` 文件所在的目录（如 `"src/"`），默认 `""`

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

### matcher:compile(prefix)

为指定目录前缀预编译一个高效的局部匹配函数。适用于遍历目录树时批量判断同一目录下多个文件的场景。

`compile` 会根据 `prefix` 从树中收集相关规则，并过滤掉明显不可能匹配的 anchored patterns（利用 `literal_prefix` 快速筛选），返回一个只做 pattern 匹配的轻量函数。结果会被缓存，同一 prefix 重复调用时直接返回缓存。

**参数：**

- `prefix` (`string|nil`): 当前遍历的目录前缀（如 `"src/core/"`），默认 `""`

**返回：**

- 局部匹配函数 `function(path, basename, is_dir)`，语义同 `matcher:match`，但不检查父目录是否被排除（适合 scan 等已保证父目录未被忽略的场景）

**示例：**

```lua
local matcher = gitignore.new({ "*.o", "!keep.o" })

-- 预编译根目录匹配函数
local match_fn = matcher:compile("")
match_fn("foo.o", "foo.o", false)     -- true
match_fn("keep.o", "keep.o", false)   -- false（取反）

-- 进入 src/ 后预编译该目录的匹配函数
matcher:push({ "!debug.o" }, "src/")
local match_src = matcher:compile("src/")
match_src("src/debug.o", "debug.o", false)  -- false（src/ 取反生效）
match_src("src/main.o", "main.o", false)    -- true
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
