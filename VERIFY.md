# verify.sh — 一条命令的离线校验

- `bash verify.sh --prime`：唯一允许联网的形态。只备料、不下结论：装 JDK 17（若本机没有）、拉 Gradle wrapper 发行版、用 `--write-locks` 生成依赖锁文件、把校验要用的依赖全部解析进缓存。
- `bash verify.sh`：全程 `--offline`，一个外网请求都不发。依次跑七关，哪关不过就地停，末行 `VERIFY FAILED: <关名>` 并非零退出；七关全过末行 `VERIFY OK`。

## 七关各自卡什么

### toolchain
整棵树所有 Kotlin/Java 编译和测试任务落在同一个固定 JDK 主版本（17）上，且三处一字不差：`buildSrc/src/main/kotlin/kotlin-conventions.gradle.kts` 的 `jvmToolchain(17)`、`.github/workflows/*.yml` 里所有 `setup-java` 的 `java-version`、`verify.sh` 里的 `EXPECTED_JDK_MAJOR`。`settings.gradle.kts` 不允许再出现 foojay 自动下载插件；校验路径上不下载 JDK，本机找不到 JDK 17 就直接失败并打出期望版本号。Gradle wrapper 发行版必须已由 `--prime` 备好，Gradle 自身（launcher JVM）也必须是 17。

### single-source
扫整棵树所有 `*.gradle.kts`，任何 `"group:name:version"` 形式的字面量都算不过。跨 classpath 共享的版本（`kotlin.version`、`kotest.version`、`vanniktech.version`）只在 `gradle.properties` 里定义一次：主构建的 version catalog 和 `kotlin-conventions` 用 `providers.gradleProperty(...)` 读，`buildSrc`（独立构建，不继承根 `gradle.properties`）直接读根目录那份文件。因此 buildSrc 的 `kotlin-gradle-plugin` 与 catalog 里的 Kotlin 必然同版本（2.2.21）。

### locks
Gradle 自带 dependency locking，只读不写。`:hoplite-core` 等 11 个受验模块和 `buildSrc` 都必须有落盘的 `gradle.lockfile`；校验时以 `-Pverify.strict.locks=true` 开严格模式（`LockMode.STRICT`）离线解析这 11 个模块的全部可解析配置——锁文件缺失、对不上、多出一条都会让构建失败。`--write-locks` 只出现在 `--prime` 里。严格模式挂在命令行属性上，不影响 `master.yml`/`pr.yml` 里 `./gradlew check` 对未锁模块（AWS/Azure/GCP 等）的既有行为。

### offline-build
`--offline` 下编译 11 个模块（hoplite-core、hoplite-yaml、hoplite-json、hoplite-toml、hoplite-hocon、hoplite-datetime、hoplite-arrow、hoplite-cronutils、hoplite-vavr、hoplite-javax、hoplite-watch）的主代码和测试代码（`testClasses`），再用 `verify/verify.init.gradle.kts` 里的 `verifyNoForbiddenDeps` 任务把这 11 个模块解析出来的整张依赖图过一遍：出现 `com.amazonaws`、`software.amazon.awssdk`、`aws.sdk.kotlin`、`com.google.cloud`、`com.azure`、`com.orbitz.consul`、`org.apache.hadoop`、`org.springframework.vault` 中任何一个 group 即判不过。

### offline-test
同样 11 个模块的测试，仍然 `--offline`。`hoplite-core` 里起 postgres 容器的 `HostnameValidatorTest`、`JdbcHostnameValidatorTest` 通过 `hoplite-core/build.gradle.kts` 里的 `tasks.test { exclude(...) }` 排掉（构建配置排除，不删文件）。跑完按模块各打一行 `tests :<模块>=<n>`，n 取自该模块本次 JUnit XML 结果中 `tests - skipped` 的总和；任何一个模块 n 为 0 即判不过——`isFailOnNoMatchingTests = false` 造成的"静默零用例"在这里兜不住。

### examples
两个游离在 `include(...)` 之外的工程，逐个给出明确结论：

- **example-maven：EXCLUDED。** `maven.pom` 钉的是 Maven Central 上已发布的 `com.sksamuel.hoplite:1.0.7` 和 `kotlin 1.3.50`，跑它验证的是那些历史发布产物，不是当前源码树；仓库里也没有 maven wrapper 能在离线前提下复现它。若 pom 里的版本钉发生变化，这一关会失败并要求重新评估结论。
- **example-native：EXCLUDED。** 它的 hoplite 依赖是 `com.sksamuel.hoplite:hoplite-core:_` 占位符版本，只有配合 `includeBuild("..")` 替换才有意义；且其存在意义是 GraalVM native-image 构建，`org.graalvm.buildtools.native` 插件和 GraalVM 工具链都无法在离线前提下备齐并给出可信结论。若占位符写法变化，这一关同样失败并要求重新评估。

### clean-tree
脚本开头存一份 `git status --porcelain` 快照，七关跑完再取一份，不一致就把差出来的路径打出来判不过。锁文件、`verify.sh`、新工作流都是要进版本库的内容，这一关比的是"跑校验"这件事有没有回头改工作区，不靠 `.gitignore` 遮。

## CI

`.github/workflows/verify.yml`：checkout → `setup-java` 装 JDK 17（与 toolchain 关认定的主版本一致）→ `bash verify.sh --prime`（唯一联网 step）→ `bash verify.sh`（纯离线）。不使用任何依赖缓存 action，冷启动不被掩盖。
