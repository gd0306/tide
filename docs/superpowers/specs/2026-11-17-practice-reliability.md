# 潮语可靠性与实用练习改进

用户已批准执行项目审查后的计划。此次交付修复数据可靠性、构建与发行准备问题，并完成首选功能组合：今日五分钟练习、纠错重说、收藏表达。历史双语复习、入门配置说明和必要的大字号问题一并处理。第二批慢速跟读、主动回忆评分、周报、云同步不属于此次实施。

## 必须保持

- 英文 Tide、中文潮语；内部 TideEnglish、cn.gd306.tideenglish、TIDE_ENGLISH_* 不变。
- 已有应用标识、存储路径、部署身份及 schemaVersion 1/2 备份可读性不变。新学习内容使用可缺省的 schema 2 扩展字段，两端一致。
- 登录、托管、内购、云同步默认关闭；不部署、不发布、不推送、不安装真实设备应用、不读取真实密钥、不自动发起真实模型或语音调用。
- 收藏、查看答案和纠错重说不虚构独立口语掌握证据。修改、删除来源和撤回同意必须使迟到结果失效。
- 测试只使用合成档案、凭据和故障。先验证失败，再实现，再验证通过。工程变更通过 tools/generate_project.py。
- 保持现有 Paper/Midnight/Grove 与原生导航、表单、Sheet 的视觉方向，中英文完整，支持辅助字号和减少动态效果。

## 数据可靠性

导入和删除的成功必须代表持久化完成，失败不能提交成功状态；iOS 导入外来未结束记录时设 endedAt 和明确导入结束原因。Android 必须等待写入完成，失败恢复旧档案，禁止后续排队的旧快照把失败操作重新写入。

iOS 最终评估使用有界、持久化、设备私有的恢复票据，不导出、不从导入档案新建 AI 工作。最多尝试三次，只处理七天内明确排队的最新未评估用户回合；每次前台最多五个，尊重有效供应商同意、供应商身份、已保存 Key、删除/修订及托管边界。失败状态可见并可手动重试。恢复票据与学习快照原子提交。

启动错误提供真实重试、用户主动导出原始学习档案和从备份恢复的操作；不自动清空或覆盖损坏数据。保护原始文件，恢复替换前写私有安全副本。长期档案的学习投影按版本缓存，避免每次视图访问重复全量投影。

## 共享练习协议

Archive 增加可选 `practice: PracticeLibrary?`（Kotlin 默认 null）；缺失时按空集合处理。`PracticeLibrary` 包含 `expressions: [SavedExpression]`、`corrections: [SavedCorrection]`。集合最多各 2,000 条，验证已支持语言、UUID、日期、非空文本及长度；导入按 ID 合并并去重，保留本机偏好。旧档案和契约 fixture 无需新增必填字段。

`SavedExpression`：`id` UUID、`languageID` String、`text` String（最多 2,000 字符）、`meaning` String（最多 4,000）、`context` String（最多 4,000）、`createdAt` Date、可选 `sourceSessionID` UUID、`sourcePassageID` String、`revisionKey` String。按语言和规范化原文去重，重复收藏返回已有项目。用户可删除。保存的表达不作为 LearningEngine 的独立证据。

`SavedCorrection`：`id` UUID、`languageID`、`original`、`corrected`（各最多 2,000）、`explanation`（最多 4,000）、`createdAt`、`sourceSessionID` UUID、`sourcePassageID`、`revisionKey`、可选 `rehearsedAt`。必须对应尚未改变的用户原句；删除或修改来源时移除相关纠错，禁止迟到 AI 响应重新创建。

SessionRecord 增加可选 `practiceKind: String?`，值仅允许 daily/correction。纠错练习全部词汇证据最多记为 assisted，不计独立回忆。会话仍沿用现有字段、语音及评估协议。

共享核心提供：`DailyPracticePlan.make(...)`（从到期词取最多三个，选择本语言有效场景，没有历史也能练），`PracticeLibrary` 的收藏、删除、修订失效和合并操作，`PracticeCorrectionResult` 校验，以及 `PracticePrompts.correction(languageName:meaningLanguage:)`。纠错 API 返回 JSON `{"hasCorrection": Bool,"corrected": String,"explanation": String}`；没有明确错误时不保存为纠错、不伪造错误；返回内容绑定请求时原句与修订。提问、解释和错误全部本地化。

## 原生使用流程

对话页增加紧凑的今日五分钟入口，预览场景、最多三个复习词及目标，点击开始后才发起已有的 Key/同意/麦克风流程，运行限时五分钟，不改用户常规 sessionMinutes 偏好。保存 practiceKind=daily。

词汇页增加“收藏表达”和“纠错本”的清晰入口，使用单独列表页或原生 sheet。查词详情、单词详情、历史句子允许显式收藏；显示重复收藏反馈。收藏列表支持当前语言的本地搜索、详情和删除。

历史页显示缓存双语译文并支持本地搜索。用户选中已结束会话中的本人原句后，可主动请求纠错；结果展示原句、建议、解释，明确成功、没有错误、错误与重试状态，主动保存至纠错本。点击“重说一次”回到对话并启动以该意图为目标的新场景，标记 practiceKind=correction；已有活动会话期间禁用相关修改/新建操作。

模型设置解释凭据、文本与原生实时语音的区别；不通过自动网络检查制造费用。功能用完整原生 UI 流程验证，不只编译数据结构。

## 发行准备与工程

将真实链接和主体/备案信息集中到可核对的发行配置。未知主体姓名、备案号、授权协议、正式页面域名不得编造。提供可直接编辑的页面内容与发行检查，缺项应阻止正式发行验收，不阻止普通 Debug 开发。默认用户可读本地隐私说明，不能继续点击无效示例域名。

iOS CI 增加生成工程一致性、arm64 模拟器构建和少量离线 UI；修复品牌测试误扫 Git 忽略目录；文档准确区分 iOS App 26.1 与 Swift Core 17。Android 调整 AAB 语言分发以支持应用内中英文切换，词条长文本可滚动。

## 验收

受影响 Swift/Kotlin 单测、根工具、语言导出与跨端契约通过；双端 Debug 构建和 Android lint 通过；新功能原生模拟器测试涵盖首屏入口、收藏去重、纠错请求/重试/来源失效、五分钟偏好不变、历史译文、最大字号。故障测试证明未落盘不报成功、评估不从导入档案自动发起、撤回和删除不恢复数据。报告未做的真机、在线模型、备案、部署与商店发布工作。
