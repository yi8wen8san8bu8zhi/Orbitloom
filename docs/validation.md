# 首版验证记录

日期：2026-10-30

## 脚本结果底部抽屉的验证

本次只调整脚本执行结果的呈现与入口：结果从主窗口底部向上展开，配置编辑保留现有弹窗。未改变脚本执行、停止、配置存储和日志持久化逻辑。

实际变更：

| 文件 | 变更 |
| --- | --- |
| `Orbitloom/Views/RunResultsDrawer.swift`（新增） | 结果选择信息、抽屉中的脚本身份与状态、停止和收起操作；抽取原日志视图供结果抽屉与目录日志页签共用 |
| `Orbitloom/ContentView.swift` | 主窗口底部覆盖层与展开/收起动画；所属项目移除时关闭对应结果 |
| `Orbitloom/Views/ProjectDetailView.swift` | 脚本启动后打开结果抽屉，脚本日志入口改为「查看结果」；目录主命令保留原日志页签 |
| `Orbitloom/Views/ProjectFilesView.swift` | 文件行及已配置脚本增加结果入口；脚本详情关闭后再通过回调打开结果抽屉 |
| `docs/requirements.md`、`docs/implementation.md`、`docs/validation.md` | 同步结果抽屉需求、使用方式和本次验证记录 |

静态核对覆盖：底部对齐及从底部移动的过渡；查看结果只加载对应 UUID 的日志而不启动脚本；收起按钮与 Esc 不调用停止；停止只针对当前结果实例；文件失效时可从历史记录直接查看结果；脚本面板关闭回调再展开结果；脚本结果切换时重建日志视图；目录日志页签的跟随输出选择保留在原详情状态中。

相对本次修改前快照的差异及空白格式检查通过，包含新增文件；`git diff --check` 通过。保留此前未提交修改，未改动工程配置、图标、模型、服务层或真实脚本。只执行一次 Debug 构建：

```sh
xcodebuild -project Orbitloom.xcodeproj -scheme Orbitloom \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /var/folders/zd/k3sl5mpn431c4_j603kk3f8c0000gn/T/Orbitloom-result-drawer.lyt1tiz3/build \
  CODE_SIGNING_ALLOWED=NO build
```

结果：`BUILD SUCCEEDED`，无 Swift 编译错误或警告；Xcode 仅提示未依赖 AppIntents.framework，跳过元数据提取。日志位于 `/var/folders/zd/k3sl5mpn431c4_j603kk3f8c0000gn/T/Orbitloom-result-drawer.lyt1tiz3/build.log`；本次差异保存在同目录 `changes.patch`。

未执行回归测试、临时断言程序、原生界面操作或真实脚本。待手动验收：启动后脚本面板关闭与底部动画、320 点抽屉在不同窗口大小下的布局、实时输出与滚动跟随、停止、复制、Esc 收起、重新打开和切换脚本结果。可先运行新版本，通过已配置脚本的「查看结果」验收展开与收起，不必执行真实脚本。

## 目录内脚本浏览与运行的验证

本次按确认方案新增目录内脚本运行，不修改用户的脚本文件，也不直接收录真实目录。保留修改前已有的项目代码、图标和工程配置。

### 实际变更文件

| 文件 | 本次变更 |
| --- | --- |
| `Orbitloom/Services/ProjectFileBrowser.swift`（新增） | 逐层读取目录、识别脚本与 SQL 文件、校验目录内文件位置、生成绝对路径启动草稿 |
| `Orbitloom/Views/ProjectFilesView.swift`（新增） | 文件导航、刷新、已配置脚本与历史日志、独立脚本详情面板及读取失败反馈 |
| `Orbitloom/Models/Project.swift` | 保存脚本相对路径、稳定 UUID 和独立配置；旧资料缺少 `scripts` 时按空数组解码 |
| `Orbitloom/Services/ProjectParser.swift` | 为目录内脚本提供绝对路径命令选项，已有独立项目解析沿用原默认行为 |
| `Orbitloom/Services/ProjectStore.swift` | 保存独立脚本配置；启动和保存入口校验脚本位置；重新定位时更新目录并取消确认 |
| `Orbitloom/Services/RunManager.swift` | 汇总项目及其脚本状态，复用现有受管进程与独立 UUID 日志机制 |
| `Orbitloom/Views/ProjectDetailView.swift` | 增加文件页签，复用详情和日志界面展示当前脚本，连接配置与启动入口 |
| `Orbitloom/Views/ProjectEditorView.swift` | 按所属目录保存脚本配置；脚本面板只编辑运行设置，不改所属项目元数据 |
| `Orbitloom/ContentView.swift` | 侧栏、批量选择和移除校验纳入目录内脚本的活动状态 |
| `docs/requirements.md`、`docs/implementation.md`、`docs/validation.md` | 更新需求范围、使用流程、持久化说明和本次验证记录 |

### 实际执行的验证

仅执行源代码静态核对、相对修改前快照的差异与空白格式检查，以及一次 Debug 构建。没有运行回归测试、临时断言程序、原生界面操作、真实资料库读写或任何用户脚本。

静态核对覆盖：目录导航与忽略规则；SQL 不提供启动入口；各脚本配置和日志标识独立；保存前无资料库写入；旧字段解码默认值；目录刷新和标签修改保留脚本配置；更换工作目录时命令仍引用脚本绝对路径；目录重新定位后要求再次确认；文件失效后保留日志与停止入口；父项目活动状态纳入脚本运行状态；退出应用沿用现有全部实例清理流程。这些核对不代表已经通过运行时验收。

相对快照的 `git diff --no-index --check` 未报告空白问题（退出码 1 表示存在文件差异），`git diff --check` 通过。差异文件保存在 `/var/folders/zd/k3sl5mpn431c4_j603kk3f8c0000gn/T/Orbitloom-script-files.5r095sby/changes.patch`。

```sh
xcodebuild -project Orbitloom.xcodeproj -scheme Orbitloom \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /var/folders/zd/k3sl5mpn431c4_j603kk3f8c0000gn/T/Orbitloom-script-files.5r095sby/build \
  CODE_SIGNING_ALLOWED=NO build
```

结果：`BUILD SUCCEEDED`，无 Swift 编译错误或警告。Xcode 仅提示未依赖 AppIntents.framework，跳过元数据提取。构建日志位于 `/var/folders/zd/k3sl5mpn431c4_j603kk3f8c0000gn/T/Orbitloom-script-files.5r095sby/build.log`。

### 待手动验收与已知边界

后续使用新构建运行应用，添加“葵花宝典”目录，进入「文件」，选择 `gitlab-group-clone.js`，核对环境和工作目录后保存并启动。此脚本会将仓库克隆到所选工作目录，应按实际输出位置设置。SQL 文件只展示运行条件提示。

尚未验收：原生界面布局、子目录导航、取消与保存、重启后配置及日志恢复、两个脚本的独立状态、缺少解释器、真实脚本执行与停止、文件失效后的日志入口、移动目录后的再次确认。不会自动安装运行环境，不提供 SQL 执行、交互式终端或文件改名后的配置自动迁移。

## 标签筛选与搜索框同排布局的验证

修改 `ContentView.swift`，将搜索框和标签筛选放入同一个水平容器，搜索框位于左侧并占剩余空间，筛选控件位于右侧且固定为 100 点宽。移除筛选控件原有的独立外边距，隐藏重复的「标签」标题，默认选项显示「全部标签」，设置长标签单行尾部省略，并保留无障碍名称。同步更新实现说明中的控件位置。

仅执行本次差异核对、空白格式检查和一次 Debug 构建，结果通过。筛选条件、项目数据和清除操作逻辑未变。没有运行回归测试或原生界面操作验收；窄侧栏、长标签及搜索和标签同时有清除按钮时的实际显示效果待手动确认。

```sh
xcodebuild -project Orbitloom.xcodeproj -scheme Orbitloom \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/Orbitloom-tag-layout.c3wxeg5v/build \
  CODE_SIGNING_ALLOWED=NO build
```

结果：`BUILD SUCCEEDED`，无 Swift 编译错误或警告；Xcode 仅提示未依赖 AppIntents.framework，跳过元数据提取。日志：`/tmp/Orbitloom-tag-layout.c3wxeg5v/build.log`。

## 本次标签与标签过滤的验证

按确认范围，仅执行源代码静态核对、变更差异及空白格式检查和一次 Debug 构建。没有运行回归测试、临时断言程序、真实资料库读写、项目启动或原生界面操作验收。

静态核对内容：

- 项目新增 `tags` 字段，旧资料缺失该字段时解码为空数组，其余字段沿用原有解码要求，编码保留全部现有字段。
- 标签输入支持中英文逗号及换行，去除首尾空白、空标签和完全相同的重复项；输入草稿与保存入口共用解析规则。
- 手动添加时标签随项目保存，重复路径不覆盖原标签；标签单独保存只更新最新资料中的目标项目标签，不校验或确认运行配置。取消不写入，写入失败时保留草稿。
- 刷新、重新定位及运行配置保存没有覆盖标签字段，扫描新增项目默认无标签。
- 名称／用途搜索与「全部／无标签／具体标签」过滤取交集，批量勾选沿用当前过滤结果；添加或打开已有项目后清除搜索及标签过滤。
- 标签菜单汇总整个资料库；当前标签已无人使用时保留选择和空结果。无匹配结果时提供清除入口。
- 核对本次修改前的文件快照与现有文件差异，保留此前未提交修改；本次涉及文件的空白格式检查通过，包括新增标签组件及原有未跟踪文件。

构建命令：

```sh
xcodebuild -project Orbitloom.xcodeproj -scheme Orbitloom \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/Orbitloom-tags.uo4_w7s2/build \
  CODE_SIGNING_ALLOWED=NO build
```

结果：`BUILD SUCCEEDED`，无 Swift 编译错误或警告；Xcode 提示未依赖 AppIntents.framework，跳过元数据提取。日志：`/tmp/Orbitloom-tags.uo4_w7s2/build.log`。

待手动验收：添加项目时填写标签；未配置或运行中的项目独立编辑标签；中英文分隔符、空白及重复输入；复用已有标签、移除和取消；保存后重启及刷新保留标签；组合搜索与三种标签过滤；过滤后批量全选；删除最后一个被使用的标签；长标签显示、空结果和保存失败反馈。旧资料库兼容与重启持久化目前仅完成源代码核对，尚未通过运行时读写验证。

## 本次手动添加流程的验证

本次仅执行源代码静态核对和 Debug 构建，没有运行回归测试、临时断言程序、被添加的项目或原生界面操作验收。

静态核对：左侧资料库、顶部工具栏、空状态及 ⌘O 共用添加表单；选择路径仅更新草稿，保存时校验名称并重新读取路径；自定义名称与用途保存到现有字段，刷新不覆盖；重复路径打开已有项目；保存成功后清空搜索并选中条目；保存失败保留草稿；运行配置仍待确认。

```sh
xcodebuild -project Orbitloom.xcodeproj -scheme Orbitloom \
  -configuration Debug -derivedDataPath /tmp/Orbitloom-scan-review.3zfAUT/build \
  CODE_SIGNING_ALLOWED=NO build
```

结果：`BUILD SUCCEEDED`，无 Swift 编译错误或警告；仅有跳过 AppIntents 元数据提取的 Xcode 提示。日志：`/tmp/Orbitloom-manual-add.j7k5tezr/build.log`。本次差异和空白格式检查通过。

待手动验收：从侧栏进入并选择目录或脚本；修改名称与用途后保存；取消不收录；重复路径打开原项目；搜索状态下添加后可见；空白名称、无权限、路径失效或保存失败时的反馈。

## 候选确认流程的验证（此前改动）

该次验证仅包含源代码静态核对和 Debug 构建，没有运行回归测试、临时断言程序、被扫描的脚本或原生界面操作验收。下方首版历史结果不代表新流程已经通过这些验证。

静态核对内容：

- 应用启动和刷新按钮只调用 `refreshProjects()`；刷新只读取已有路径，不添加或删除条目。
- `addLocation()` 只保存扫描位置；`discoverProjects()` 只返回候选，未调用资料库保存。
- 候选默认不勾选；只有「添加所选」调用 `addDiscoveredProjects()`，重新读取所选路径、排除重复路径并一次保存。失败时预览与勾选保留。
- Maven / Gradle 声明作为项目边界，候选扫描排除 `mvnw`、`gradlew`；手动添加及已有条目刷新仍允许这些脚本。
- 核对本次差异与空白格式，保留原有未提交修改。

构建命令：

```sh
xcodebuild -project Orbitloom.xcodeproj -scheme Orbitloom \
  -configuration Debug -derivedDataPath /tmp/Orbitloom-scan-review.3zfAUT/build \
  CODE_SIGNING_ALLOWED=NO build
```

结果：`BUILD SUCCEEDED`，无 Swift 编译错误或警告；仅有未依赖 AppIntents.framework 而跳过元数据提取的 Xcode 提示。日志位于 `/tmp/Orbitloom-scan-review.3zfAUT/build.log`。

待手动验收：启动不新增项目；候选默认不勾选；取消不收录；部分勾选只添加所选项；刷新保留已保存配置；Maven 目录不展开 `mvnw`；无权限或候选文件失效时的错误反馈。既有误收录条目未自动清理，可通过批量移除功能处理。

## 首版历史验证

- Xcode 26.6 / Apple Swift 6.3.3，macOS arm64。
- Debug 构建命令：

```sh
xcodebuild -project Orbitloom.xcodeproj -scheme Orbitloom \
  -configuration Debug -derivedDataPath /tmp/Orbitloom-build \
  CODE_SIGNING_ALLOWED=NO build
```

- 结果：`BUILD SUCCEEDED`。无 Swift 编译警告；Xcode 提示未使用 AppIntents.framework，跳过对应元数据提取。
- 第一次构建发现 C 字符串数组的 Swift 类型推断错误，已修正。旧的工作目录接口也已替换为当前 SDK 接口，后续构建通过。
- 在实现完成后，用项目内相同的 Model/Service 源码编译临时验证程序，没有先编写测试驱动实现，也没有添加或运行回归测试套件。
- 验证目录：`/tmp/Orbitloom-validation.SJsqoG`。样例、数据、日志与被执行命令均限制在该临时目录；使用已存在的 Python/Node.js 环境，没有安装依赖。
- 核心流程的 **42 项针对性断言全部通过**，其中包含异步运行退出的超时断言。

| 验证范围 | 结果 |
| --- | --- |
| 重叠目录去重、不同路径副本分别收录 | 通过 |
| 项目内部脚本归属、忽略依赖/虚拟环境/构建目录 | 通过 |
| Python 元数据、脚本用途、Git origin、环境模板名称 | 通过 |
| 多入口不自动选择，扫描不执行样例脚本 | 通过 |
| JSON 保存、600 文件权限、重新加载 | 通过 |
| 重扫保留用户名称/简介/命令/备注 | 通过 |
| 路径缺失保留信息，重新定位调整目录且要求复核 | 通过 |
| Python、npm 声明命令、含空格与单引号路径的 Shell 实际运行 | 通过 |
| 自定义环境变量和缺失必需变量提示 | 通过 |
| stdout/stderr、非零退出码、一次性完成与服务退出区分 | 通过 |
| 主动停止、后代清理、同名无关进程保持运行 | 通过 |
| 自定义停止命令获得 PID/PGID，停止超时强制结束 | 通过 |
| 超过 1 MB 的日志有界保存，尾部保留，重启读取 | 通过 |
| 验证完成后无受管实例遗留 | 通过 |

原生界面已启动并检查空状态、项目添加面板，以及收录项目后的列表、详情、配置入口和固定启动/停止区。核心配置与运行行为通过临时程序验证；没有宣称完成全部原生界面的逐项操作验收。

## 后续手动验收清单

1. 在设置中添加两个实际扫描目录，确认未新增项目；打开「扫描发现」检查项目边界，勾选添加后再次扫描确认已收录路径不再作为候选。
2. 选择一个已准备好环境的真实 Python/Node.js/Shell 项目，核对识别来源并确认入口。
3. 补充用途、备注和运行配置，保存后重启应用，再按名称或用途查找。
4. 一次性脚本正常完成后检查「执行完成」；故意使用错误参数时检查失败日志。
5. 启动前台服务，观察日志，停止并确认实际资源已释放。
6. 修改原项目声明再刷新，确认已保存的用户配置保持不变。
7. 移动项目后刷新，重新定位并核对绝对路径和脚本名称。
8. 有活动实例时退出应用，分别检查取消退出与停止并退出。

真实复杂项目、交互式命令、版本兼容性、强制退出后的进程恢复、发布签名与公证未验证。交互式命令和脱离进程组的守护程序不属于首版支持范围。
