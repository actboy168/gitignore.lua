-- 统一测试数据集
-- 每个用例:
--   name: 测试名称
--   patterns: .gitignore 模式列表
--   paths: { { path, is_dir, expected }, ... }
--     expected: true=被忽略, false=不被忽略, nil=由git对比决定
--   ignore_case: 可选，是否忽略大小写

return {
    -- 1. 空行和注释
    {
        name = "blank line",
        patterns = { "" },
        paths = {
            { "foo", false, false },
        },
    },
    {
        name = "comment",
        patterns = { "# comment", "*.o" },
        paths = {
            { "foo.o", false, true },
            { "bar.c", false, false },
        },
    },
    {
        name = "escaped hash",
        patterns = { [==[\#file]==] },
        paths = {
            { "#file", false, true },
            { "file", false, false },
        },
    },

    -- 2. 尾部空格
    {
        name = "trailing spaces stripped",
        patterns = { "foo  " },
        paths = {
            { "foo", false, true },
        },
    },
    {
        name = "escaped trailing space",
        patterns = { [==[foo\ ]==] },
        paths = {
            { "foo ", false, true },
            { "foo", false, false },
        },
    },

    -- 3. 取反
    {
        name = "negation basic",
        patterns = { "*.o", "!foo.o" },
        paths = {
            { "foo.o", false, false },
            { "bar.o", false, true },
        },
    },
    {
        name = "negation parent excluded",
        patterns = { "dir/", "!dir/file.txt" },
        paths = {
            { "dir", true, true },
            { "dir/file.txt", false, true },
        },
    },
    {
        name = "escaped exclamation",
        patterns = { [==[\!file]==] },
        paths = {
            { "!file", false, true },
            { "file", false, false },
        },
    },

    -- 4. 目录模式
    {
        name = "dir only matches directory",
        patterns = { "foo/" },
        paths = {
            { "foo", true, true },
            { "foo", false, false },
        },
    },
    {
        name = "without slash matches both",
        patterns = { "foo" },
        paths = {
            { "foo", true, true },
            { "foo", false, true },
        },
    },
    {
        name = "dir excludes contents",
        patterns = { "dir/" },
        paths = {
            { "dir/file.txt", false, true },
        },
    },
    {
        name = "dir exact prefix not suffix",
        patterns = { "git/" },
        paths = {
            { "git", true, true },
            { "git/foo", false, true },
            { "git-foo", false, false },
            { "git-foo/bar", false, false },
        },
    },

    -- 5. 锚定模式
    {
        name = "leading slash anchors",
        patterns = { "/foo" },
        paths = {
            { "foo", false, true },
            { "a/foo", false, false },
        },
    },
    {
        name = "middle slash anchors",
        patterns = { "foo/bar" },
        paths = {
            { "foo/bar", false, true },
            { "a/foo/bar", false, false },
        },
    },
    {
        name = "no slash matches any depth",
        patterns = { "foo" },
        paths = {
            { "foo", false, true },
            { "a/foo", false, true },
            { "a/b/foo", false, true },
        },
    },

    -- 6. * 通配符
    {
        name = "star matches basename",
        patterns = { "*.o" },
        paths = {
            { "foo.o", false, true },
            { "foo.c", false, false },
            { "dir/foo.o", false, true },
        },
    },
    {
        name = "star in path",
        patterns = { "foo/*" },
        paths = {
            { "foo/bar", false, true },
            { "foo/bar/baz", false, true },
        },
    },
    {
        name = "star matches empty",
        patterns = { "f*o" },
        paths = {
            { "fo", false, true },
            { "foo", false, true },
            { "fabcdo", false, true },
        },
    },
    {
        name = "star does not match slash",
        patterns = { "foo/bar/*" },
        paths = {
            { "foo/bar/baz", false, true },
            { "foo/bar/baz/qux", false, true },
        },
    },

    -- 7. ? 通配符
    {
        name = "question matches single char",
        patterns = { "f?o" },
        paths = {
            { "foo", false, true },
            { "fao", false, true },
            { "fo", false, false },
        },
    },
    {
        name = "question no match slash",
        patterns = { "f?o" },
        paths = {
            { "f/o", false, false },
        },
    },

    -- 8. 方括号表达式
    {
        name = "bracket character class",
        patterns = { "[abc].o" },
        paths = {
            { "a.o", false, true },
            { "b.o", false, true },
            { "d.o", false, false },
        },
    },
    {
        name = "bracket range",
        patterns = { "[a-z].o" },
        paths = {
            { "a.o", false, true },
            { "m.o", false, true },
            { "A.o", false, false },
        },
    },
    {
        name = "bracket range ignore case",
        ignore_case = true,
        patterns = { "[a-z].o" },
        paths = {
            { "A.o", false, true },
        },
    },
    {
        name = "bracket negation bang",
        patterns = { "[!abc].o" },
        paths = {
            { "a.o", false, false },
            { "d.o", false, true },
        },
    },
    {
        name = "bracket negation caret",
        patterns = { "[^abc].o" },
        paths = {
            { "a.o", false, false },
            { "d.o", false, true },
        },
    },
    {
        name = "bracket no match slash",
        patterns = { "[a/].o" },
        paths = {
            { "a.o", false, true },
            { "/.o", false, false },
        },
    },

    -- 9. ** 模式
    {
        name = "doublestar prefix",
        patterns = { "**/foo" },
        paths = {
            { "foo", false, true },
            { "a/foo", false, true },
            { "a/b/foo", false, true },
        },
    },
    {
        name = "doublestar suffix",
        patterns = { "abc/**" },
        paths = {
            { "abc/x", false, true },
            { "abc/x/y/z", false, true },
        },
    },
    {
        name = "doublestar middle",
        patterns = { "a/**/b" },
        paths = {
            { "a/b", false, true },
            { "a/x/b", false, true },
            { "a/x/y/b", false, true },
        },
    },
    {
        name = "doublestar non delimited",
        patterns = { "a**b" },
        paths = {
            { "ab", false, true },
            { "axb", false, true },
            { "axyb", false, true },
            { "a/x/b", false, false },
        },
    },
    {
        name = "doublestar requires slash separator",
        patterns = { "foo**/bar" },
        paths = {
            { "foo/bar", false, true },
            { "foobar", false, false },
        },
    },
    {
        name = "doublestar with extension",
        patterns = { "**/*.log" },
        paths = {
            { "debug.log", false, true },
            { "logs/debug.log", false, true },
            { "a/b/debug.log", false, true },
        },
    },
    {
        name = "doublestar negation dirs and txt",
        patterns = { "data/**", "!data/**/", "!data/**/*.txt" },
        paths = {
            { "data/file", false, true },
            { "data/data1/file1", false, true },
            { "data/data1/file1.txt", false, false },
            { "data/data2/file2", false, true },
            { "data/data2/file2.txt", false, false },
        },
    },

    -- 10. 反斜杠转义
    {
        name = "escape star",
        patterns = { [==[\*.o]==] },
        paths = {
            { "*.o", false, true },
            { "foo.o", false, false },
        },
    },
    {
        name = "escape question",
        patterns = { [==[f\?o]==] },
        paths = {
            { "f?o", false, true },
            { "foo", false, false },
        },
    },
    {
        name = "escape bracket",
        patterns = { [==[\[abc]]==] },
        paths = {
            { "[abc]", false, true },
            { "a", false, false },
        },
    },

    -- 11. 无效尾部反斜杠
    {
        name = "trailing backslash never matches",
        patterns = { [==[foo\]==] },
        paths = {
            { "foo", false, false },
            { [==[foo\]==], false, false },
        },
    },

    -- 12. 最后匹配的模式优先
    {
        name = "last matching wins",
        patterns = { "*.o", "!foo.o", "foo.o" },
        paths = {
            { "foo.o", false, true },
            { "bar.o", false, true },
        },
    },
    {
        name = "negate then re-negate",
        patterns = { "*.o", "!foo.o" },
        paths = {
            { "foo.o", false, false },
            { "bar.o", false, true },
        },
    },

    -- 13. 父目录排除不可覆盖
    {
        name = "parent exclusion blocks negation",
        patterns = { "dir/", "!dir/file.txt" },
        paths = {
            { "dir", true, true },
            { "dir/file.txt", false, true },
        },
    },
    {
        name = "parent exclusion deep",
        patterns = { "a/", "!a/b/c.txt" },
        paths = {
            { "a/b/c.txt", false, true },
        },
    },
    {
        name = "no parent exclusion allows negation",
        patterns = { "*.txt", "!foo.txt" },
        paths = {
            { "foo.txt", false, false },
            { "bar.txt", false, true },
        },
    },
    {
        name = "ignored dir contents all excluded",
        patterns = { "ignored-dir/" },
        paths = {
            { "ignored-dir", true, true },
            { "ignored-dir/foo", false, true },
            { "ignored-dir/twoooo", false, true },
            { "ignored-dir/sub/deep", false, true },
        },
    },

    -- 14. 大小写
    {
        name = "default case sensitive",
        patterns = { "Foo" },
        paths = {
            { "Foo", false, true },
            { "foo", false, false },
        },
    },
    {
        name = "ignore case",
        ignore_case = true,
        patterns = { "Foo" },
        paths = {
            { "Foo", false, true },
            { "foo", false, true },
            { "FOO", false, true },
        },
    },
    {
        name = "ignore case with star",
        ignore_case = true,
        patterns = { "*.O" },
        paths = {
            { "foo.o", false, true },
            { "foo.O", false, true },
        },
    },

    -- 15. 边界情况
    {
        name = "empty patterns",
        patterns = {},
        paths = {
            { "foo", false, false },
        },
    },
    {
        name = "multiple patterns",
        patterns = { "*.o", "*.a", "!keep.o" },
        paths = {
            { "foo.a", false, true },
            { "keep.o", false, false },
            { "other.o", false, true },
        },
    },
    {
        name = "path with subdirs",
        patterns = { "/doc/*.pdf" },
        paths = {
            { "doc/report.pdf", false, true },
            { "src/doc/report.pdf", false, false },
        },
    },
    {
        name = "comment and blank lines",
        patterns = { "# comment", "", "*.o" },
        paths = {
            { "foo.o", false, true },
        },
    },
    {
        name = "anchored dir pattern with slash",
        patterns = { "/git/" },
        paths = {
            { "git", true, true },
            { "git/foo", false, true },
            { "git-foo", false, false },
            { "git-foo/bar", false, false },
        },
    },
    {
        name = "star prefix pattern",
        patterns = { "*three" },
        paths = {
            { "3-three", false, true },
            { "three-not-this-one", false, false },
        },
    },
    {
        name = "negated prefix pattern",
        patterns = { "one", "ignored-*", "!on*" },
        paths = {
            { "one", false, false },
            { "on", false, false },
            { "only", false, false },
            { "other", false, false },
        },
    },

    -- ===== 回归测试（由 fuzz git 对比发现） =====

    -- FIX: star 优化搜索 next_literal 时，先检查匹配再检查 / 边界
    -- a/*/b/*/c 应匹配 a/x/b/y/c
    {
        name = "regression multi star path",
        patterns = { "a/*/b/*/c" },
        paths = {
            { "a/x/b/y/c", false, true },
            { "a/b/b/b/c", false, true },
            { "a/b/c", false, false },
        },
    },

    -- FIX: ] 紧跟 [ 后应视为字面量
    -- []abc] 中 ] 是字符类成员
    {
        name = "regression bracket close after open",
        patterns = { "[]abc].o" },
        paths = {
            { "].o", false, true },
            { "a.o", false, true },
            { "b.o", false, true },
            { "d.o", false, false },
        },
    },

    -- FIX: 连续 / 应规范化
    -- foo//bar 等价于 foo/bar
    {
        name = "regression double slash",
        patterns = { "foo/bar" },
        paths = {
            { "foo//bar", false, true },
        },
    },

    -- 边界：仅含 / 的模式
    {
        name = "slash only pattern",
        patterns = { "/" },
        paths = {
            { "foo", false, false },
        },
    },

    -- 边界：空取反模式
    {
        name = "empty negation pattern",
        patterns = { "!" },
        paths = {
            { "foo", false, false },
        },
    },

    -- 边界：*** 视为 ** + *（连续星号）
    {
        name = "triple star",
        patterns = { "***" },
        paths = {
            { "foo", false, true },
            { "a/b", false, true },
        },
    },

    -- 边界：**/ ** 双星号组合
    {
        name = "doublestar doublestar",
        patterns = { "**/**" },
        paths = {
            { "foo", false, true },
            { "a/b", false, true },
        },
    },

    -- ===== 覆盖率补充测试 =====

    -- FIX: bracket ignore_case 时 [ABC] 不匹配小写 a
    -- 原因: ignore_case 回退检查只查 chars[tc_orig]，未查 chars[tc_orig:upper()]
    -- skip_git: Windows git bracket ignore_case 行为不同
    {
        name = "regression bracket ignore case chars upper",
        ignore_case = true,
        skip_git = true,
        patterns = { "[ABC].o" },
        paths = {
            { "A.o", false, true },
            { "a.o", false, true },
            { "d.o", false, false },
        },
    },

    -- 覆盖 line 72-74: [ 在模式末尾视为字面量
    -- skip_git: Windows 文件名不允许 [ 字符
    {
        name = "bracket open at end",
        skip_git = true,
        patterns = { "abc[" },
        paths = {
            { "abc[", false, true },
            { "abc", false, false },
        },
    },

    -- 覆盖 line 101-103: 方括号内 \ 转义在末尾（未闭合）
    {
        name = "bracket backslash escape at end unclosed",
        patterns = { [==[[a\]==] },
        paths = {
            { "a", false, false },
        },
    },

    -- 覆盖 line 110-111: 方括号范围结束符转义 [a-\z]
    {
        name = "bracket range end escaped",
        patterns = { [==[[a-\z]]==] },
        paths = {
            { "a", false, true },
            { "m", false, true },
            { "z", false, true },
        },
    },

    -- 覆盖 line 124-125: 未闭合方括号 [ 视为字面量
    -- skip_git: Windows 文件名不允许 [ 字符
    {
        name = "unclosed bracket literal",
        skip_git = true,
        patterns = { "[abc" },
        paths = {
            { "[abc", false, true },
            { "a", false, false },
        },
    },

    -- 覆盖 line 168-169: strip_trailing_spaces 中 break（非空格字符中断循环）
    {
        name = "trailing spaces with middle spaces",
        patterns = { "foo  bar  " },
        paths = {
            { "foo  bar", false, true },
            { "foo", false, false },
        },
    },

    -- 覆盖 line 189: 偶数尾部反斜杠（\\ → 字面量 \）
    -- skip_git: Windows 路径分隔符差异
    {
        name = "even trailing backslashes",
        skip_git = true,
        patterns = { [==[foo\\]==] },
        paths = {
            { [==[foo\]==], false, true },
        },
    },

    -- 覆盖 line 287: star 后跟 bracket
    {
        name = "star then bracket",
        patterns = { "*[abc].o" },
        paths = {
            { "xa.o", false, true },
            { "xd.o", false, false },
        },
    },

    -- 覆盖 line 289: star 后跟 question
    {
        name = "star then question",
        patterns = { "*?.o" },
        paths = {
            { "ab.o", false, true },
            { "a.o", false, true },
        },
    },

    -- 覆盖 line 291: star 后跟 doublestar
    {
        name = "star then doublestar",
        patterns = { "a/**/b" },
        paths = {
            { "a/b", false, true },
            { "a/x/b", false, true },
        },
    },

    -- 覆盖 line 328: star 无优化时消耗全部字符（* 位于模式末尾，无后续 literal）
    {
        name = "star alone at end no optimization",
        patterns = { "foo*" },
        paths = {
            { "foo", false, true },
            { "foobar", false, true },
            { "foo/bar", false, true },
        },
    },

    -- 覆盖 line 373-375: bracket ignore_case 原始大小写 chars 检查
    -- 覆盖 m.load: 从文件加载 gitignore（由 test.lua 单独测试）
}
