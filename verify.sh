#!/usr/bin/env bash
#
# verify.sh - one-command, offline-capable verification for this repository.
#
#   bash verify.sh --prime   Provision everything verification needs (ONLY
#                            mode allowed to use the network): JDK, Gradle
#                            wrapper distribution, dependency lock files and
#                            the dependency cache. Draws no conclusions.
#
#   bash verify.sh           Run the seven gates below, fully offline
#                            (every Gradle invocation uses --offline):
#                            toolchain, single-source, locks, offline-build,
#                            offline-test, examples, clean-tree.
#
# Last line of output is either "VERIFY OK" or "VERIFY FAILED: <gate>".

set -euo pipefail

cd "$(dirname "$0")"
ROOT=$(pwd)

# ---------------------------------------------------------------------------
# Constants (single-sourced here; the toolchain gate cross-checks them against
# kotlin-conventions.gradle.kts and the CI workflows).
# ---------------------------------------------------------------------------
EXPECTED_JDK_MAJOR=17

MODULES=(
  hoplite-core hoplite-yaml hoplite-json hoplite-toml hoplite-hocon
  hoplite-datetime hoplite-arrow hoplite-cronutils hoplite-vavr
  hoplite-javax hoplite-watch
)

INIT_SCRIPT="$ROOT/verify/verify.init.gradle.kts"
GRADLE_USER_HOME="${GRADLE_USER_HOME:-$HOME/.gradle}"
LOG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/verify-logs.XXXXXX")
GRADLE_RUN=0

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------
tasks_for() { # tasks_for <task> -> ":m1:task :m2:task ..."
  local task="$1" m
  for m in "${MODULES[@]}"; do printf ':%s:%s ' "$m" "$task"; done
}

jdk_major() { # jdk_major <java-home> -> major version number
  local v
  v=$("$1/bin/java" -version 2>&1 | head -n 1 | sed -E 's/^[^"]*"([^"]*)".*/\1/')
  case "$v" in
    1.*) echo "$v" | cut -d. -f2 ;;
    *)   echo "$v" | cut -d. -f1 ;;
  esac
}

find_jdk_home() { # find_jdk_home <major> -> prints java home, or fails
  local expected="$1" c home
  if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/java" ] \
     && [ "$(jdk_major "$JAVA_HOME")" = "$expected" ]; then
    echo "$JAVA_HOME"; return 0
  fi
  if [ -x /usr/libexec/java_home ]; then
    c=$(/usr/libexec/java_home -v "$expected" 2>/dev/null || true)
    if [ -n "$c" ] && [ -x "$c/bin/java" ]; then echo "$c"; return 0; fi
  fi
  for c in /usr/lib/jvm/* "$GRADLE_USER_HOME"/jdks/*; do
    home="$c"
    [ -x "$home/bin/java" ] || home="$c/Contents/Home"
    if [ -x "$home/bin/java" ] && [ "$(jdk_major "$home")" = "$expected" ]; then
      echo "$home"; return 0
    fi
  done
  return 1
}

use_jdk() { # pin every Gradle invocation to the given JDK, downloads disabled
  export JAVA_HOME="$1"
  GRADLE_BASE_OPTS=(
    --console=plain
    -Dorg.gradle.java.installations.auto-download=false
    "-Dorg.gradle.java.installations.paths=$1"
  )
}

run_gradle() { # run_gradle <args...> -> dumps log tail and fails on error
  local log="$LOG_DIR/gradle-$((GRADLE_RUN += 1)).log"
  if ! ./gradlew "${GRADLE_BASE_OPTS[@]}" "$@" >"$log" 2>&1; then
    echo "--- gradle $* (failed, tail of $log) ---"
    tail -n 60 "$log"
    return 1
  fi
}

count_tests() { # count_tests <module> -> executed test count from JUnit XML
  local dir="$1/build/test-results/test" tests=0 skipped=0
  if [ -d "$dir" ]; then
    tests=$(grep -ho 'tests="[0-9]*"' "$dir"/*.xml 2>/dev/null | cut -d'"' -f2 | awk '{s+=$1} END {print s+0}')
    skipped=$(grep -ho 'skipped="[0-9]*"' "$dir"/*.xml 2>/dev/null | cut -d'"' -f2 | awk '{s+=$1} END {print s+0}')
  fi
  echo $((tests - skipped))
}

# ---------------------------------------------------------------------------
# Gate framework
# ---------------------------------------------------------------------------
GATE=""
run_gate() {
  GATE="$1"; shift
  echo "==> $GATE"
  if "$@"; then
    echo "[OK] $GATE"
  else
    echo "[FAIL] $GATE"
    echo "VERIFY FAILED: $GATE"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Gate 1: toolchain - one fixed JDK major everywhere, resolved locally only.
# ---------------------------------------------------------------------------
gate_toolchain() {
  local conv="buildSrc/src/main/kotlin/kotlin-conventions.gradle.kts"
  local conv_jdk
  conv_jdk=$(grep -oE 'jvmToolchain\([0-9]+\)' "$conv" | grep -oE '[0-9]+' | head -n 1)
  if [ "$conv_jdk" != "$EXPECTED_JDK_MAJOR" ]; then
    echo "kotlin-conventions.gradle.kts uses jvmToolchain($conv_jdk), expected $EXPECTED_JDK_MAJOR"
    return 1
  fi
  local wf versions
  for wf in .github/workflows/*.yml .github/workflows/*.yaml; do
    [ -f "$wf" ] || continue
    grep -q 'setup-java' "$wf" || continue
    versions=$(grep -E '^[[:space:]]*java-version:' "$wf" \
      | sed -E "s/.*java-version:[[:space:]]*['\"]?([0-9]+).*/\1/" | sort -u)
    if [ "$versions" != "$EXPECTED_JDK_MAJOR" ]; then
      echo "$wf declares java-version '$versions', expected '$EXPECTED_JDK_MAJOR'"
      return 1
    fi
  done
  if grep -q 'foojay' settings.gradle.kts; then
    echo "settings.gradle.kts still registers the foojay toolchain resolver (auto-download)"
    return 1
  fi
  local dist_version
  dist_version=$(grep '^distributionUrl' gradle/wrapper/gradle-wrapper.properties \
    | sed -E 's/.*gradle-([0-9.]+)-all\.zip.*/\1/')
  if ! ls "$GRADLE_USER_HOME/wrapper/dists/gradle-$dist_version-all"/*/ >/dev/null 2>&1; then
    echo "Gradle $dist_version wrapper distribution not provisioned; run: bash verify.sh --prime"
    return 1
  fi
  local jdk
  if ! jdk=$(find_jdk_home "$EXPECTED_JDK_MAJOR"); then
    echo "JDK $EXPECTED_JDK_MAJOR not found locally and downloads are forbidden here."
    echo "Run 'bash verify.sh --prime' to provision JDK $EXPECTED_JDK_MAJOR."
    return 1
  fi
  use_jdk "$jdk"
  local launcher_jvm
  launcher_jvm=$(./gradlew "${GRADLE_BASE_OPTS[@]}" --version 2>/dev/null \
    | grep -E '^Launcher JVM:' | sed -E 's/[^0-9]*([0-9]+).*/\1/')
  if [ "$launcher_jvm" != "$EXPECTED_JDK_MAJOR" ]; then
    echo "Gradle launcher JVM is $launcher_jvm, expected $EXPECTED_JDK_MAJOR"
    return 1
  fi
  echo "JDK $EXPECTED_JDK_MAJOR ($jdk) drives compile, test and Gradle itself"
}

# ---------------------------------------------------------------------------
# Gate 2: single-source - no literal group:name:version in any *.gradle.kts;
# versions shared across classpaths come from gradle.properties only.
# ---------------------------------------------------------------------------
gate_single_source() {
  local hits
  hits=$(find . -name '*.gradle.kts' \
      -not -path './.git/*' -not -path './.gradle/*' -not -path '*/build/*' \
      -print0 | xargs -0 grep -nE '"[A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+:[0-9][^"]*"' || true)
  if [ -n "$hits" ]; then
    echo "literal group:name:version coordinates found:"
    echo "$hits"
    return 1
  fi
  local prop
  for prop in kotlin.version kotest.version vanniktech.version; do
    if [ "$(grep -c "^$prop=" gradle.properties)" != "1" ]; then
      echo "gradle.properties must define $prop exactly once"
      return 1
    fi
  done
  grep -q 'gradleProperty("kotlin.version")' settings.gradle.kts || {
    echo "version catalog does not read kotlin.version from gradle.properties"; return 1; }
  grep -q 'getProperty("kotlin.version")' buildSrc/build.gradle.kts || {
    echo "buildSrc does not read kotlin.version from gradle.properties"; return 1; }
  grep -q 'getProperty("vanniktech.version")' buildSrc/build.gradle.kts || {
    echo "buildSrc does not read vanniktech.version from gradle.properties"; return 1; }
  grep -q 'gradleProperty("kotest.version")' buildSrc/src/main/kotlin/kotlin-conventions.gradle.kts || {
    echo "kotlin-conventions does not read kotest.version from gradle.properties"; return 1; }
  local kotlin_version
  kotlin_version=$(grep '^kotlin.version=' gradle.properties | cut -d= -f2)
  echo "kotlin $kotlin_version is single-sourced for both buildSrc and main classpaths"
}

# ---------------------------------------------------------------------------
# Gate 3: locks - every classpath resolved during verification has a lock
# file; strict mode, offline, read-only (no --write-locks anywhere here).
# ---------------------------------------------------------------------------
gate_locks() {
  local m
  for m in "${MODULES[@]}"; do
    if [ ! -f "$m/gradle.lockfile" ]; then
      echo "missing lock file: $m/gradle.lockfile (run: bash verify.sh --prime)"
      return 1
    fi
  done
  if [ ! -f buildSrc/gradle.lockfile ]; then
    echo "missing lock file: buildSrc/gradle.lockfile (run: bash verify.sh --prime)"
    return 1
  fi
  # Strict-mode resolution of every resolvable configuration of the verified
  # modules. buildSrc is locked strictly as well: it is rebuilt (and thus
  # resolved) by every one of these invocations under -Pverify.strict.locks.
  run_gradle --offline -Pverify.strict.locks=true -I "$INIT_SCRIPT" \
    $(tasks_for verifyResolveAllConfigurations)
}

# ---------------------------------------------------------------------------
# Gate 4: offline-build - compile main+test of the verified modules offline;
# resolved graph must not contain any cloud/SDK dependency group.
# ---------------------------------------------------------------------------
gate_offline_build() {
  run_gradle --offline -Pverify.strict.locks=true $(tasks_for testClasses) || return 1
  run_gradle --offline -Pverify.strict.locks=true -I "$INIT_SCRIPT" \
    $(tasks_for verifyNoForbiddenDeps)
}

# ---------------------------------------------------------------------------
# Gate 5: offline-test - run the verified modules' tests offline and prove
# each module actually executed at least one test.
# ---------------------------------------------------------------------------
gate_offline_test() {
  local m
  for m in "${MODULES[@]}"; do
    rm -rf "$m/build/test-results/test" "$m/build/reports/tests"
  done
  run_gradle --offline -Pverify.strict.locks=true $(tasks_for test) || return 1
  local n
  for m in "${MODULES[@]}"; do
    n=$(count_tests "$m")
    echo "tests :$m=$n"
    if [ "$n" -eq 0 ]; then
      echo "module :$m executed 0 tests"
      return 1
    fi
  done
}

# ---------------------------------------------------------------------------
# Gate 6: examples - explicit verdict for each detached example project.
# ---------------------------------------------------------------------------
gate_examples() {
  local pom="example-maven/maven.pom"
  if ! grep -q '<hoplite.version>1.0.7</hoplite.version>' "$pom" \
     || ! grep -q '<kotlin.version>1.3.50</kotlin.version>' "$pom"; then
    echo "example-maven/maven.pom no longer pins hoplite 1.0.7 / kotlin 1.3.50; re-evaluate its verdict"
    return 1
  fi
  echo "example-maven: EXCLUDED - pins published com.sksamuel.hoplite:1.0.7 and kotlin 1.3.50 from Maven Central; building it verifies those released artifacts, not this source tree"
  if ! grep -q 'com.sksamuel.hoplite:hoplite-core:_' example-native/build.gradle.kts; then
    echo "example-native no longer uses the '_' version placeholder; re-evaluate its verdict"
    return 1
  fi
  echo "example-native: EXCLUDED - depends on placeholder version '_' (only meaningful via includeBuild substitution) and its purpose requires a GraalVM native-image toolchain, which cannot be provisioned or validated offline"
}

# ---------------------------------------------------------------------------
# Gate 7: clean-tree - verification itself must not modify the work tree.
# ---------------------------------------------------------------------------
gate_clean_tree() {
  local after
  after=$(git status --porcelain)
  if [ "$after" != "$TREE_SNAPSHOT" ]; then
    echo "verification modified the work tree:"
    diff <(printf '%s\n' "$TREE_SNAPSHOT") <(printf '%s\n' "$after") || true
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Prime mode: provision only, no conclusions.
# ---------------------------------------------------------------------------
prime() {
  echo "==> prime: JDK $EXPECTED_JDK_MAJOR"
  local jdk
  if jdk=$(find_jdk_home "$EXPECTED_JDK_MAJOR"); then
    echo "found JDK $EXPECTED_JDK_MAJOR at $jdk"
  else
    echo "installing Temurin JDK $EXPECTED_JDK_MAJOR into $GRADLE_USER_HOME/jdks"
    install_jdk
    jdk=$(find_jdk_home "$EXPECTED_JDK_MAJOR") || {
      echo "prime failed: JDK $EXPECTED_JDK_MAJOR still not found after install"; exit 1; }
  fi
  use_jdk "$jdk"

  echo "==> prime: Gradle wrapper distribution"
  ./gradlew "${GRADLE_BASE_OPTS[@]}" --version >/dev/null

  echo "==> prime: dependency lock files (--write-locks happens only here)"
  run_gradle -I "$INIT_SCRIPT" $(tasks_for verifyResolveAllConfigurations) --write-locks || exit 1
  run_gradle -p buildSrc -I "$INIT_SCRIPT" verifyResolveAllConfigurations --write-locks || exit 1

  echo "==> prime: resolving and caching everything verification needs"
  run_gradle $(tasks_for testClasses) || exit 1
  run_gradle -I "$INIT_SCRIPT" $(tasks_for verifyNoForbiddenDeps) || exit 1
  run_gradle $(tasks_for test) || exit 1

  echo "PRIME COMPLETE"
}

install_jdk() {
  local os arch
  case "$(uname -s)" in
    Darwin) os=mac ;;
    Linux)  os=linux ;;
    *) echo "prime failed: unsupported OS $(uname -s)"; exit 1 ;;
  esac
  case "$(uname -m)" in
    arm64|aarch64) arch=aarch64 ;;
    x86_64|amd64)  arch=x64 ;;
    *) echo "prime failed: unsupported arch $(uname -m)"; exit 1 ;;
  esac
  local url="https://api.adoptium.net/v3/binary/latest/${EXPECTED_JDK_MAJOR}/ga/${os}/${arch}/jdk/hotspot/normal/eclipse"
  local tmp
  tmp=$(mktemp -d)
  curl -fL --retry 3 "$url" -o "$tmp/jdk.tar.gz" || { rm -rf "$tmp"; echo "prime failed: JDK download failed"; exit 1; }
  mkdir -p "$GRADLE_USER_HOME/jdks"
  tar -xzf "$tmp/jdk.tar.gz" -C "$GRADLE_USER_HOME/jdks" || { rm -rf "$tmp"; echo "prime failed: JDK extract failed"; exit 1; }
  rm -rf "$tmp"
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
case "${1:-}" in
  --prime)
    prime
    ;;
  "")
    TREE_SNAPSHOT=$(git status --porcelain)
    run_gate toolchain     gate_toolchain
    run_gate single-source gate_single_source
    run_gate locks         gate_locks
    run_gate offline-build gate_offline_build
    run_gate offline-test  gate_offline_test
    run_gate examples      gate_examples
    run_gate clean-tree    gate_clean_tree
    echo "VERIFY OK"
    ;;
  *)
    echo "usage: bash verify.sh [--prime]" >&2
    exit 2
    ;;
esac
