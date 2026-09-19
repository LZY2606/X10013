# verify.sh — 一条命令的离线校验

`bash verify.sh --prime` 是唯一联网的形态：只备料（装 JDK、暖 wrapper、下载全部依赖、
写依赖锁文件），不下任何结论。`bash verify.sh` 全程 `--offline`，顺序跑七关，
每关打印 `==> 关名` 与 `[OK] 关名` / `[FAIL] 关名`；任一关失败就地停止，末行
`VERIFY FAILED: 关名` 并非零退出；七关全过末行 `VERIFY OK`。

## toolchain

卡的是「整棵树同一个 JDK 主版本」。

- 固定版本是 **JDK 17**，三处一字不差：`verify.sh` 里的 `EXPECTED_JDK_MAJOR`、
  `buildSrc/src/main/kotlin/kotlin-conventions.gradle.kts` 的 `jvmToolchain(17)`、
  `.github/workflows/*.yml` 里所有 `java-version`。
- 全树扫描所有 `*.gradle.kts`，不允许出现第二个 `jvmToolchain(...)` 数值。
- `settings.gradle.kts` 里的 `foojay-resolver-convention` 插件已删除——那是校验路径上
  自动下载 JDK 的来源；Gradle 调用还额外加了
  `-Dorg.gradle.java.installations.auto-download=false`。
- 本机找不到 JDK 17 时直接失败并打出期望版本号；要装就在 `--prime` 里装
  （Temurin 17，装进 `~/.gradle/jdks/`，Gradle 自动探测得到）。

## single-source

卡的是「外部坐标只有一个出处」。

- 唯一出处是 `gradle/libs.versions.toml`：主构建按默认位置自动导入为 `libs`，
  `buildSrc/settings.gradle.kts` 显式 `from(files("../gradle/libs.versions.toml"))`
  导入同一个文件，两条 classpath 读到的是同一份坐标。
- 扫描整棵树所有 `*.gradle.kts`，任何 `"group:name:version"` 字面量（第三段以数字
  开头）都算不过。原来写死在 `buildSrc/build.gradle.kts` 的
  `kotlin-gradle-plugin:2.2.10`、vanniktech 插件 `0.35.0` 和
  `kotlin-conventions.gradle.kts` 里三条 `io.kotest:kotest-*:6.1.4` 都已搬进目录。
- 目录内部不允许同一个 module 出现两个版本；`kotlin-gradle-plugin`（buildSrc 侧）
  与 `kotlin-jvm` 插件（主构建侧）必须共用同一个 version.ref，现在都是
  `kotlin = "2.2.21"`。

## locks

卡的是「每条解析外部依赖的 classpath 都有锁，且严格匹配」。

- 24 个模块 + `buildSrc` + settings 各自有落盘的 `gradle.lockfile`
  （`settings-gradle.lockfile` 在根上），缺任何一个都不过。
- 锁只在校验路径启用：`-Pverify.locks` 开 `lockAllConfigurations()`，
  `-Pverify.locks.strict` 加 `LockMode.STRICT`。`verifyLockedResolution` 任务把
  全树每个可解析 configuration 在 `--offline` 下只读解析一遍——锁文件缺失、
  对不上、多出一条都会让 Gradle 直接报错。
- `--write-locks` 只出现在 `--prime` 里（`resolveAndLockAll` 任务还带
  `require(isWriteDependencyLocks)` 保险）；`bash verify.sh` 路径上没有任何
  会写回仓库文件的动作。

## offline-build

卡的是「核心 11 模块离线编译，且依赖图里没有云厂商 SDK」。

- `--offline` 下跑 `:hoplite-core … :hoplite-watch` 共 11 个模块的 `testClasses`
  （主代码 + 测试代码一起编译）。
- `verifyNoForbiddenDeps` 任务解析这 11 个模块的 `runtimeClasspath` 与
  `testRuntimeClasspath`，出现 `com.amazonaws`、`software.amazon.awssdk`、
  `aws.sdk.kotlin`、`com.google.cloud`、`com.azure`、`com.orbitz.consul`、
  `org.apache.hadoop`、`org.springframework.vault` 中任何一个 group 即失败。

## offline-test

卡的是「同样 11 个模块的测试离线真跑，且每个模块都跑到了用例」。

- `--offline` 跑 11 个模块的 `test`；`hoplite-core` 里起 `postgres:13.7`
  容器的 `HostnameValidatorTest`、`JdbcHostnameValidatorTest` 通过
  `-Pverify.excludeContainerTests` 在构建配置里 `excludeTestsMatching` 排掉，
  文件原样保留。
- 结束后按模块统计本次真正执行的用例数（JUnit XML 的 `tests - skipped`），
  逐行打印 `tests :hoplite-core=<n>`；任何一个模块 `n=0` 即失败——
  `isFailOnNoMatchingTests = false` 造成的「一个没跑也不吭声」在这里被堵住。

## examples

两个游离工程都给出明确结论，且结论所依据的事实每轮都会被重新核对，
事实变了（比如占位符被改掉）这一关会失败要求重新评估，而不是无声跳过。

- **example-maven：排除。** `maven.pom` 钉的是 Maven Central 上已发布的
  `com.sksamuel.hoplite:1.0.7` 和 `kotlin 1.3.50`，跑它验证的是两年前的发布产物，
  不是当前这棵树；它也不在 `include(...)` 里，没有接进本仓库的构建。
- **example-native：排除。** `build.gradle.kts` 依赖
  `com.sksamuel.hoplite:hoplite-core:_` / `hoplite-yaml:_`，`_` 版本占位符根本
  无法解析；另外它需要 GraalVM native-image 工具链，`verify.sh` 不备这个料。

## clean-tree

卡的是「校验本身不往工作区写东西」。

- 脚本开头存一份 `git status --porcelain` 快照，末尾再取一份比对，
  差出来的路径逐条打出并判失败。锁文件、`verify.sh`、新工作流都是提交进
  版本库的正式内容，这一关比的是跑校验的过程有没有回头改它们。
- 连敲两遍 `bash verify.sh` 都是 `VERIFY OK`。

## CI

`.github/workflows/verify.yml`：checkout → `setup-java` 装 JDK 17（与 toolchain
认定的主版本一致）→ `bash verify.sh --prime`（唯一联网步骤）→ `bash verify.sh`
（全离线）。不使用任何依赖缓存 action，冷启动不被掩盖。

## 附：快照修复说明

环境快照因为 `.gitignore` 的 `env/` 和 `.env.*` 规则弄丢了两个源码文件：
`hoplite-core/src/main/kotlin/com/sksamuel/hoplite/env/Environment.kt` 和
`hoplite-core/src/test/resources/.env.properties`（后者正是 `Github350` 注释里
说的那个文件，上游仓库其实是提交的）。已按上游 `sksamuel/hoplite` master 原文
恢复，并在 `.gitignore` 里加了这两条路径的反向规则，保证它们能进版本库——
否则从零 checkout 的机器上 `hoplite-core` 根本无法编译。
