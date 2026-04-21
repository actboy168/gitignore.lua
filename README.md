# gitignore.lua

符合 git 完整规范的 `.gitignore` 模式匹配 Lua 库。

## 安装

单文件库，将 `gitignore.lua` 复制到项目中即可。

## 用法

```lua
local gitignore = require "gitignore"

-- 从模式列表创建
local matcher = gitignore.new({
    "*.o",
    "!keep.o",
    "build/",
})

matcher:match("foo.o", false)        -- true
matcher:match("keep.o", false)       -- false（取反）
matcher:match("build", true)         -- true （目录模式）
matcher:match("src/main.c", false)   -- false

-- 忽略大小写
local matcher = gitignore.new({ "Foo" }, { ignore_case = true })
matcher:match("foo", false)          -- true
```

## API

| API | 说明 |
|-----|------|
| `gitignore.new(patterns, opts)` | 从模式列表创建匹配器 |
| `matcher:match(path, is_dir)` | 判断路径是否被忽略 |
| `matcher:push(lines, prefix)` | 动态追加规则（栈式） |
| `matcher:pop()` | 还原上次 push 的规则 |
| `matcher:compile(prefix)` | 为指定目录预编译高效匹配函数 |

**选项：**

- `opts.ignore_case` (`boolean`，默认 `false`)：忽略大小写匹配

## 测试

```bash
luamake lua test.lua                        # 单元测试
luamake lua test.lua -c                     # 单元测试 + 覆盖率
luamake lua test.lua -g                    # 单元测试 + git 对比
```

## 许可证

MIT
