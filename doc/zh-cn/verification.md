# 验证

## 仓库检查

运行 `python3 tool/check_docs.py` 和 `python3 tool/check_dependencies.py`。后者解析中立包，
若其引入具体后端或声明插件则失败。CI 检查文档路径、标题层级、表格行数和相同代码块，
以及本地 Markdown 链接。检查器不验证翻译含义，需同时审阅两种语言。

包检查在维护者使用的 Flutter（3.47.6）上运行，ffigen 22 生成绑定需要该版本。
`python3 tool/check_consumer_resolution.py <dir>` 创建依赖全部包的应用，并在消费者使用的
Flutter（3.44.2）上解析；依赖约束使用版本范围以便消费者解析。

自 0.6.0 起：`model_naming_test` 检查 92 个真实与虚构 id；`myapps_ai_sources` 用假后端测试路由、
持久化、GPU 选择、自定义模型与诊断，设置 `LLAMA_TEST_MODEL` 时还实际生成一次，并确认诊断不含提示文本；
在线测试覆盖多模型记录及迁移、模型列表解析、目录、全部模板和管理器；部件测试覆盖来源区块、诊断复制、
模板与模型选择、双栏来源库、服务端点选择和自定义模型警告。`check_dependencies.py` 还会在
`myapps_ai_sources` 解析到 `myapps_ai_online` 时失败。

## 实现验收

原生 CI 生成临时 Flutter 宿主，构建 Android ARM64 release APK，以及未签名 iOS
和 macOS release 应用。Apple 包使用 `tool/check_weak_link.sh` 检查。这些检查验证
编译、插件包含和链接；旧系统启动和模型推理仍需设备或模拟器。

ASR 后端包测试运行各自的构建 hook，在 CI 主机上加载预构建库，并在无模型情况下检查
路线、指纹和错误。实机推理通过环境变量启用：`LASR_TEST_MODEL`（whisper GGML 模型）与
`QWEN_TEST_DIR`（解压后的 Qwen3-ASR 包），转写自带的 JFK 样本。Apple 桥接只在 macOS 和
iOS 加载，其他平台的路线不可用。`asr-native-prebuild` 与 `asr-apple-prebuild` 工作流只
构建上游未发布的二进制，需手动运行。

llama.cpp 包测试检查清单、加载上游库，并在不加载的情况下检查缺失模型。`ggml_layout_test` 检查各平台查找 ggml 的位置（含 Android 库路径位于 APK 内的情况），并按分数选出最佳 CPU 变体。有模型时还检查 GPU 回退（已记录的失败与加载失败都在 CPU 上运行）和设备列表。设置
`LLAMA_TEST_MODEL`（小型 GGUF 对话模型）后启用流式、确定性、token 上限、停止串、取消、
忙碌、上下文上限和重新加载检查。同一应用进程不得加载两套不同的 ggml；捆绑 ggml 的包在
其 ggml 对齐或隔离之前不得同时使用。

引入包时，在 CI 添加格式化、分析及有意义的测试。注入后端和时钟，检查独立能力、
关闭门控、可用性刷新、未知状态、总量未知的下载进度、队列顺序、重试次数、前后台
切换、取消、超时和晚到结果。使用缓存时检查兼容性和过期结果丢弃。

验证 Android release 构建的 R8 和原生插件注册。验证 Apple 构建的 Foundation Models
弱链接及旧系统启动。仅在 Linux 验证无法证明 Apple 二进制兼容。

消费者回归检查保留确定性决策、事实边界、评分和生成内容规则。验证各应用支持的
界面语言和授权声明。真机检查记录硬件、系统、模型和测试能力；模拟测试和云端替代
模型不能证明设备端推理质量。
