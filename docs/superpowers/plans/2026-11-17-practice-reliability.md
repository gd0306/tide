# Tide Practice Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox syntax.

**Goal:** 完成已批准的数据可靠性改进和今日练习、纠错重说、收藏表达，补齐发行与 CI 基础。

**Architecture:** 保持现有本地优先原生双端架构，使用可选 schema 2 扩展保存用户主动收藏和纠错；设备恢复状态与公开备份分离。新增独立练习核心与原生视图，复用现有模型、语音、同意、存储流程。

**Tech Stack:** Swift 6 core / SwiftUI iOS 26.1、Kotlin / Compose Android API 26+、Python tools、GitHub Actions。

**Spec:** `docs/superpowers/specs/2026-11-17-practice-reliability.md`

## Global Constraints

- Tide / 潮语；内部 TideEnglish、cn.gd306.tideenglish、TIDE_ENGLISH_* 稳定。
- 不启用登录、托管、内购或同步，不部署、不发布、不推送、不安装真实设备应用；使用合成数据。
- 旧 schema 1/2 兼容，新字段可缺省，两端一致；收藏和纠错练习不能虚构独立掌握证据。
- 新工程文件通过 `python3 tools/generate_project.py` 生成。现有个人 Team 和 Key 不得写入仓库。
- 原生主题与交互保持，新增功能中英文与大字号可用。
- 只有一个实施代理同时修改文件；控制者可处理互不重叠的工程任务，评审只读。

### Task 1: 数据保存、导入和故障恢复

**Files:** iOS `Application/Storage.swift`, `TideEnglishApp.swift`, `ConversationCoordinator.swift`, `LibraryViews.swift` 的备份/评估状态部分；`Domain/FinalAssessmentQueue.swift` 和新的恢复核心/测试；Android `LearningRepository.kt`, `TideEnglishViewModel.kt`, `MainActivity.kt` 的导入写入部分与对应测试。

**Interfaces:** 保留 `LearningStore.importData(_:) throws`，落盘失败真实抛出且旧档案不变；Android 导入改为可等待持久化的 suspend 操作，由 Activity coroutine 调用。设备私有恢复 metadata 不进入导出，不修改根 Archive 共享字段。新恢复策略独立于供应商请求，由当前同意与 provider 身份决定是否消费。

- [ ] 先写覆盖导入失败不提交、外来未结束记录关闭、恢复次数/来源修改/删除/撤回约束的测试。最小行为例：`XCTAssertThrowsError(try transaction.importData(data)); XCTAssertEqual(transaction.archive.sessions.count, 0)`，其中故障 writer 真实抛出磁盘错误；成功 writer 必须能重新解码已保存字节。
- [ ] 运行相应 Swift / Android 测试，记录预期失败；故障边界只替换磁盘 writer，不替换待测的事务/合并逻辑。
- [ ] 实现原子候选档案提交、恢复票据和启动恢复入口，补学习投影缓存；不擅自抽象整套存储框架。
- [ ] 运行 Swift 全量和受影响 Android 测试；更新工程并编译，写任务报告、提交。

### Task 2: 共享练习协议和纯核心

**Files:** 双端 `core/Models`、新的 `PracticeLibrary`, `DailyPractice`, `PracticePrompts` 文件及测试；`LearningEngine`；跨端 fixtures / checker 按需要更新。

**Interfaces:** 严格采用 spec 的 PracticeLibrary/SavedExpression/SavedCorrection/practiceKind 字段。Swift 日期与 UUID 使用既有编码规则，Kotlin 对应 seconds since 2001/String。提供可供双端原生集成使用的明确公开 API，并在报告列出完整签名。

- [ ] 先写旧 fixture 可读、新字段双端往返、收藏重复、修订/删除失效、未知语言与过大字段拒绝的测试；用手写 fixture 验证，不用被测生成器计算期望值。
- [ ] 先写计划无历史可练、最多三词且到期优先、纠错结果不凭空制造错误、correction 会话独立证据降为 assisted 的失败测试。
- [ ] 实现最小兼容数据和 pure policy；纠错提示中的用户输入只能作为数据；新扩展合并保留原偏好。
- [ ] 跑双端核心测试、根工具与跨端契约；提交并写报告。此任务不改 Application/UI 文件。

### Task 3: iOS 练习与复习完整流程

**Files:** `Application/PracticeViews.swift`、`RootView.swift`、`LibraryViews.swift`、`ConversationCoordinator.swift`、`Storage.swift`、`ModelProviderSettingsView.swift`、`Domain/InterfacePresentation.swift`、`UITests/TideEnglishUITests.swift`，工程生成器。

**Interfaces:** 消费 Task 2 API，存储操作遵守 Task 1 事务信号。纠错请求通过既有 APIClient.respond/同意取消路径；返回绑定 sessionID/passageID/revisionKey/provider，并在修改/删除/撤回时拒绝迟到结果。今日练习的五分钟是单次覆盖，不写偏好；纠错练习标记 correction。

- [ ] 为今日入口、收藏去重/重新启动保留、历史译文、纠错错误与重试、来源失效及辅助字号新增真实 UI/核心边界测试，先证明失败。
- [ ] 新增今日预览、收藏表达与纠错本原生页面；查词/历史/词条接入显式收藏；历史搜索与缓存译文；清晰的空态/失败反馈。
- [ ] 增加纠错请求、保存和重说流程；不在构建或预览发真实模型请求；以独立合成 provider fixture 验证。
- [ ] 保持三主题、字体放大及减少动态效果，更新中英 UI catalog；修正导航字号限制和必要的小屏溢出。
- [ ] 生成工程，跑 Swift 核心、模拟器构建和针对性 UI，提交并报告截图路径与限制。

### Task 4: Android 对等练习与复习

**Files:** `TideEnglishViewModel.kt`、`ui/PracticeScreens.kt`, `TalkScreen.kt`, `LibraryScreens.kt`, `TideEnglishApp.kt`, 相关 network/core helper、中英资源及 JVM/隔离 UI 测试。

**Interfaces:** 使用 Task 2 公共字段与策略；收藏/纠错持久化依赖 Task 1 的 barrier；新会话 duration 读取 practiceKind，不改全局偏好。后台、取消、provider 变化及源记录变化使旧结果失效。

- [ ] 对新流程与边界先写失败测试；使用 UI 测试独立包和合成凭据，禁止访问用户应用数据。
- [ ] 实现今日预览/开始、收藏入口与去重反馈、纠错请求/保存/重说、双语历史及搜索；复用既有麦克风授权入口。
- [ ] 修正词条弹窗长文本滚动；新 UI 中英文、48dp 目标和大字号；配置 AAB 保留内置中英文资源。
- [ ] 运行 JVM、lint、Debug 和隔离 UI APK 构建，条件允许时跑隔离模拟器用例；提交并报告。

### Task 5: 发行配置、CI 与文档

**Files:** `tools/check_ios_release.py`, `tools/tests/test_check_ios_release.py`, `tools/tests/test_project_identity.py`, `.github/workflows/checks.yml`；`distribution/ios/` 配置和页面内容；README/指南；双端集中发行链接配置及必要的本地隐私说明。

**Interfaces:** 普通 Debug 允许缺少备案与正式 URL，但默认显示本地真实数据说明；正式发行检查必须在主体、APP备案、AI模型备案/授权或正式隐私 URL 缺失时失败，不填假号。不部署任何页面。

- [ ] 用临时 Git 仓库验证品牌扫描忽略私有备份但仍拒绝跟踪源码残留；先证明失败，再修正边界。
- [ ] 先为发行检查写缺失主体/占位域名拒绝、有效合成配置通过、默认开关关闭的行为测试。
- [ ] 提供集中配置和可发布页面内容、本地隐私说明回退；普通 UI 不再打开失效示例地址。未知发布资料保留为空并明确阻断发行。
- [ ] CI 用确定的 Xcode/arm64 目标生成工程、编译并执行小组离线 UI；文档统一 iOS App 最低 26.1，区分工具链和语言模式。
- [ ] 全量根工具/核心/构建/相关服务检查，记录无法执行的真实世界事项；不提交个人数据或生成产物。

### Task 6: 集成与独立评审

- [ ] 按任务生成 diff review package，各任务评审确认规格和质量；控制者解决所有重要问题后继续。
- [ ] 执行 Swift、Kotlin、跨端、根工具和两端构建；在专用模拟器走通新入口、保存、恢复、纠错和五分钟练习，查看三主题/辅助字号截图。
- [ ] 更新验证记录和最终全分支评审，修复具体发现，保留分支与提交供用户复核；不发布、不部署、不推送。

执行方式：用户已要求直接开始，采用本会话连续执行，不再次询问执行方式。
