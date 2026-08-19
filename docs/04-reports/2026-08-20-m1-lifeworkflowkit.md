# M1 阶段报告：LifeWorkflowKit 共享核心包

日期：2026-08-20 · 阶段：Apple 原生化 M1 · 状态：**已交付**
提示词规格：`docs/05-apple/prompts/M1-核心包.md`

---

## 一、这一步解决什么

Apple 原生化的第一块地基：把 Python 版 `lifeos/` 里已验证的**非 UI 逻辑**平移成
Swift Package，供 macOS / iOS（以及将来的 watchOS）三端共用。

关键判断：Python 版的 `models.py` / `frontmatter.py` / `stats.py` / `repository.py`
不是「参考实现」，而是**已验证的规格**——它们的 44 项测试定义了正确行为。
Swift 版必须与之**行为等价**，否则两套实现会把同一个 vault 写坏。

## 二、交付内容

```
apple/LifeWorkflowKit/                     2413 行 / 17 个文件
├── Package.swift                          macOS 14+ / iOS 17+ / watchOS 10+，Swift 6 语言模式
├── Sources/LifeWorkflowKit/
│   ├── Models/     Enums · DateOnly · ThinkingNote · Item · RunLog
│   ├── Frontmatter/ YAMLValue · Parser · ScalarParser · Emitter
│   ├── Store/      VaultRoot · AtomicWrite · VaultStore(actor)
│   ├── Stats/      Aggregations（热力图 / 生命线 / 摘要 / 连续活跃）
│   ├── Config/     AppConfig（与 Python 版共享 ~/.config/lifeos/config.json）
│   └── Services/   RunLogService(actor) · ReviewService · EventKitBridge
├── Tests/          57 项测试 / 9 个套件 / 897 行 + 7 个交叉验证夹具
└── Tools/genfixtures.sh                   用 Python 版重新生成夹具
```

### 2.1 自写 YAML 而不是引第三方库

`frontmatter/` 是本期最花功夫的部分。不用 Yams 的理由是**确定性要求高于通用性**：

1. 字段顺序必须固定，否则每次保存都产生噪音 diff，污染 git 历史；
2. 输出必须与手写笔记**逐字节同风格**（`tags: [a, b]`、
   `- {t: 2026-08-16, note: …}`、日期不加引号），保证 Obsidian、Dataview 与人眼三方都认；
3. 通用库会转义中文、重排键、给日期加引号。

解析器覆盖本项目实际用到的 YAML 子集：块映射、块序列、内联数组、流式映射、
单/双引号标量、块标量 `|` `|-` `>` `>-`、**行内注释**（`templates/idea.md` 里
`status: seed  # seed → sprout →…` 就依赖它）、嵌套结构。解析失败一律降级为
「无 frontmatter」而**不抛错**——笔记是用户资产，宁可当纯正文也不能让应用崩。

`.date` 与 `.string` 被刻意分成两个 case，用来区分「裸写的 `2026-08-16`」与
「加了引号的 `"2026-08-16"`」，这样未知字段原样写回时不会给日期平白加上引号。

### 2.2 复合 vault（落实「只迁子集」的决定）

用户决定「想法/日记上 iCloud，隐私与大体积内容留本地」。iCloud Drive **没有**
按目录排除的机制，所以只能分根存放、在应用层合并成单一视图：

- `VaultRoot` 描述一个根（路径 + 归属的顶层目录 + 是否需要文件协调）；
- `VaultStore` 扫描多个根合并成一个列表，每条记录记住自己属于哪个根；
- 新建记录按目录归属自动路由（`Inbox/Daily/Projects` → iCloud，其余 → 本地）；
- 同一相对路径在两个根都存在时，**iCloud 优先并告警**，绝不静默丢弃。

### 2.3 把平台硬约束固化进类型系统

`EventKitBridge` 的写入方法包在 `#if !os(watchOS)` 里。这不是防御性编程，而是
调研已证实的事实：watchOS 上 `saveReminder` / `saveEvent` 等 10 个 API 被标记为
`__WATCHOS_PROHIBITED`。做成编译期开关后，手表端 UI 会因为「方法不存在」而在
编译期就被迫走队列方案，不会等到运行时才失败。

## 三、验证（实际执行的命令与输出）

```
$ swift build                      # Swift 6 严格并发
Build complete! (0.10s)
警告数: 0

$ swift build --build-tests
Build complete! (0.07s)
警告数: 0

$ xcodebuild -scheme LifeWorkflowKit -destination 'generic/platform=iOS' -quiet build
退出码: 0

$ swift test
􁁛  Test run with 57 tests in 9 suites passed after 0.071 seconds.

$ swift test --filter CrossValidation
􁁛  Test "夹具存在" passed
􁁛  Test "只读打开不产生 updated 字段" passed
􁁛  Test "Swift 解析结果与 Python 逐字段一致" passed
􁁛  Test "Swift 写回内容与 Python 逐字节一致" passed
􁁛  Test "二次保存稳定（不产生噪音 diff）" passed
```

### 3.1 交叉验证的做法

夹具由 `Tools/genfixtures.sh` 用 **Python 版**对仓库里的真实笔记生成并入库：

- `*.model.json` —— Python 解析出的全部字段
- `*.expected.md` —— Python 写回的完整文件内容

Swift 测试逐字段、逐字节与之比对。这样测试既严格（比对的是另一套已验证实现的
输出，而不是我自己写的期望值），又不依赖运行期装了 Python，CI 上照样能跑。

**结果：两套独立实现在真实数据上逐字节一致。**

### 3.2 验收标准逐条对照

| M1 提示词里的验收标准 | 结果 |
|---|---|
| `swift build` / `swift test` 严格并发下零错误零警告 | ✅ 0 警告 |
| 测试数 ≥ 44，每条标明对应的 Python 用例 | ✅ **57 项**，关键用例注释了 `对应 Python: TestXxx.test_yyy` |
| 读取真实笔记 → 写回 → `diff` 无差异 | ✅ 见 3.1（与 Python 输出逐字节一致） |
| Python 写、Swift 读的交叉验证 | ✅ `CrossValidationTests` |
| 特殊字符往返：`, : " [ ] { } #`、换行、纯数字、日期形态 | ✅ `specialCharsRoundTrip` |
| 严格并发零警告 + 并发写 100 条无损坏无残留 | ✅ `concurrentWrites`（100 条全部落盘、标题无覆盖、无 `.tmp` 残留） |
| vault 不存在 / 无权限 时返回明确错误不崩溃 | ✅ `VaultError` + 扫描告警机制 |

### 3.3 一个被测试挡下来的真实问题

初版把「读取真实笔记写回后必须逐字节一致」写成了对全部 3 篇笔记的断言，结果
2 篇失败。查下来**不是 Swift 的错**：Python 版对这 2 篇同样会补 `links: []`
（模板本就含该字段，属良性归一化）。于是把断言改成更强也更正确的形式——
**Swift 的输出必须等于 Python 的输出**，而不是等于原文件。

## 四、与 Python 版的关系

两套实现现在共享同一份配置（`~/.config/lifeos/config.json`）与同一份数据格式，
可以交替读写同一个 vault。Python 版继续作为**过渡期主力**，Mac 端 Swift 应用
（M2）跑顺后再考虑退役。

## 五、下一步：M2 macOS 应用

规格见 `docs/05-apple/prompts/M2-macOS应用.md`。前置条件已全部满足
（核心包就位、无阻塞项）。M2 不需要付费开发者账号。

**已知阻塞项（不影响 M2）**：
- watchOS SDK 未安装 → M4 暂缓；
- 免费 Apple ID → CloudKit / 小组件 / Complication 不可用，M4 在架构上走不通。
