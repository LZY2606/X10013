#!/usr/bin/env bash
#
# verify.sh - one-command, offline-capable verification for this repository.
#
#   bash verify.sh --prime   Networked preparation ONLY: installs the JDK if
#                            missing, warms the Gradle wrapper, downloads every
#                            dependency and writes the dependency lock files.
#                            It draws no conclusions and never prints VERIFY OK.
#
#   bash verify.sh           Runs seven gates, every Gradle call with --offline.
#                            Prints "==> <gate>" / "[OK] <gate>" / "[FAIL] <gate>"
#                            per gate, stops at the first failure with
#                            "VERIFY FAILED: <gate>" (non-zero exit), or ends
#                            with "VERIFY OK".
#
set -euo pipefail

cd "$(dirname "$0")"

# ---------------------------------------------------------------------------
# Constants - the JDK major below is the script's own copy of the toolchain
# contract; gate "toolchain" requires it to match kotlin-conventions.gradle.kts
# and every CI workflow exactly.
# ---------------------------------------------------------------------------
EXPECTED_JDK_MAJOR=17

MODULES=(
   hoplite-core hoplite-yaml hoplite-json hoplite-toml hoplite-hocon
   hoplite-datetime hoplite-arrow hoplite-cronutils hoplite-vavr
   hoplite-javax hoplite-watch
)

ALL_MODULES=(
   hoplite-core hoplite-azure hoplite-aws hoplite-aws2 hoplite-aws-kotlin
   hoplite-arrow hoplite-consul hoplite-cronutils hoplite-datetime hoplite-gcp
   hoplite-hdfs hoplite-hikaricp hoplite-hocon hoplite-javax hoplite-json
   hoplite-micrometer-datadog hoplite-micrometer-prometheus
   hoplite-micrometer-statsd hoplite-toml hoplite-vault hoplite-vavr
   hoplite-watch hoplite-watch-consul hoplite-yaml
)

# ---------------------------------------------------------------------------
# JDK discovery (never downloads anything; downloads only happen in --prime)
# ---------------------------------------------------------------------------
jdk_major_of() {
   "$1/bin/java" -version 2>&1 | head -n 1 | sed -E 's/.*version "([0-9]+).*/\1/'
}

find_jdk() {
   local major="$1" candidate dir
   if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ] \
      && [ "$(jdk_major_of "$JAVA_HOME")" = "$major" ]; then
      echo "$JAVA_HOME"
      return 0
   fi
   if [ -x /usr/libexec/java_home ]; then
      candidate=$(/usr/libexec/java_home -v "$major" 2>/dev/null || true)
      if [ -n "$candidate" ] && [ -x "$candidate/bin/java" ]; then
         echo "$candidate"
         return 0
      fi
   fi
   for dir in \
      "$HOME"/.gradle/jdks/*/Contents/Home \
      "$HOME"/.gradle/jdks/*/*/Contents/Home \
      "$HOME"/.gradle/jdks/* \
      /Library/Java/JavaVirtualMachines/*/Contents/Home \
      /usr/lib/jvm/*; do
      if [ -x "$dir/bin/java" ] && [ "$(jdk_major_of "$dir")" = "$major" ]; then
         echo "$dir"
         return 0
      fi
   done
   return 1
}

install_jdk() {
   local major="$1" os arch url dest tarball
   case "$(uname -s)" in
      Darwin) os=mac ;;
      Linux) os=linux ;;
      *) echo "prime: unsupported OS $(uname -s)"; return 1 ;;
   esac
   case "$(uname -m)" in
      arm64|aarch64) arch=aarch64 ;;
      x86_64|amd64) arch=x64 ;;
      *) echo "prime: unsupported architecture $(uname -m)"; return 1 ;;
   esac
   url="https://api.adoptium.net/v3/binary/latest/${major}/ga/${os}/${arch}/jdk/hotspot/normal/eclipse"
   dest="$HOME/.gradle/jdks/verify-temurin-${major}"
   tarball=$(mktemp /tmp/verify-jdk.XXXXXX.tar.gz)
   echo "prime: downloading Temurin JDK $major from $url"
   curl -fSL "$url" -o "$tarball"
   rm -rf "$dest"
   mkdir -p "$dest"
   tar -xzf "$tarball" -C "$dest" --strip-components=1
   rm -f "$tarball"
   echo "prime: installed JDK $major to $dest"
}

# ---------------------------------------------------------------------------
# Gradle helpers
# ---------------------------------------------------------------------------
gradle_prime() {
   ./gradlew --console=plain "$@"
}

# Every Gradle call on the verify path goes through here: always --offline,
# never allowed to download a JDK, always under strict dependency locking.
gradle_verify() {
   ./gradlew --offline --console=plain \
      -Dorg.gradle.java.installations.auto-download=false \
      -Pverify.locks -Pverify.locks.strict "$@"
}

# ---------------------------------------------------------------------------
# Gate 1: toolchain
# ---------------------------------------------------------------------------
gate_toolchain() {
   local conventions="buildSrc/src/main/kotlin/kotlin-conventions.gradle.kts"
   local declared
   declared=$(grep -oE 'jvmToolchain\([0-9]+\)' "$conventions" | grep -oE '[0-9]+' | head -n 1 || true)
   if [ "$declared" != "$EXPECTED_JDK_MAJOR" ]; then
      echo "toolchain: $conventions declares jvmToolchain($declared), this script expects $EXPECTED_JDK_MAJOR"
      return 1
   fi
   local all
   all=$(grep -rhoE 'jvmToolchain\([0-9]+\)' --include='*.gradle.kts' --exclude-dir=build --exclude-dir=.gradle . | sort -u)
   if [ "$all" != "jvmToolchain($EXPECTED_JDK_MAJOR)" ]; then
      echo "toolchain: inconsistent jvmToolchain declarations in the tree:"
      echo "$all"
      return 1
   fi
   local wf versions v
   for wf in .github/workflows/*.yml; do
      versions=$(grep -oE "java-version:[[:space:]]*['\"]?[0-9]+" "$wf" | grep -oE '[0-9]+' | sort -u || true)
      for v in $versions; do
         if [ "$v" != "$EXPECTED_JDK_MAJOR" ]; then
            echo "toolchain: $wf uses java-version $v, expected $EXPECTED_JDK_MAJOR"
            return 1
         fi
      done
   done
   if grep -rq 'foojay' settings.gradle.kts; then
      echo "toolchain: settings.gradle.kts still applies the foojay resolver plugin (auto-downloads JDKs)"
      return 1
   fi
   local jdk
   if ! jdk=$(find_jdk "$EXPECTED_JDK_MAJOR"); then
      echo "toolchain: no local JDK with major version $EXPECTED_JDK_MAJOR found."
      echo "toolchain: expected JDK $EXPECTED_JDK_MAJOR; run 'bash verify.sh --prime' to install it."
      return 1
   fi
   export JAVA_HOME="$jdk"
   echo "toolchain: all compile/test tasks pinned to JDK $EXPECTED_JDK_MAJOR; using $JAVA_HOME"
}

# ---------------------------------------------------------------------------
# Gate 2: single-source
# ---------------------------------------------------------------------------
toml_version_value() {
   sed -n '/^\[versions\]/,/^\[/p' gradle/libs.versions.toml \
      | grep -E "^$1[[:space:]]*=" \
      | sed -E 's/.*"([^"]+)".*/\1/'
}

gate_single_source() {
   local hits
   hits=$(grep -rnE '"[A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+:[0-9][^"]*"' \
      --include='*.gradle.kts' --exclude-dir=build --exclude-dir=.gradle . || true)
   if [ -n "$hits" ]; then
      echo "single-source: hard-coded group:name:version literals found:"
      echo "$hits"
      return 1
   fi
   if [ ! -f gradle/libs.versions.toml ]; then
      echo "single-source: gradle/libs.versions.toml is missing"
      return 1
   fi
   # The main build auto-imports gradle/libs.versions.toml as "libs"; buildSrc
   # must import the very same file explicitly.
   if ! grep -q 'from(files("../gradle/libs.versions.toml"))' buildSrc/settings.gradle.kts; then
      echo "single-source: buildSrc/settings.gradle.kts does not import ../gradle/libs.versions.toml"
      return 1
   fi
   if grep -qE 'library\(|plugin\(' settings.gradle.kts; then
      echo "single-source: settings.gradle.kts still declares catalog entries inline"
      return 1
   fi
   # No module may appear in the catalog with two different versions.
   local line module version ref tmp conflicts
   tmp=$(mktemp /tmp/verify-catalog.XXXXXX)
   while IFS= read -r line; do
      module=$(echo "$line" | sed -E 's/.*module = "([^"]+)".*/\1/')
      if echo "$line" | grep -q 'version\.ref'; then
         ref=$(echo "$line" | sed -E 's/.*version\.ref = "([^"]+)".*/\1/')
         version=$(toml_version_value "$ref")
      else
         version=$(echo "$line" | sed -E 's/.*version = "([^"]+)".*/\1/')
      fi
      printf '%s %s\n' "$module" "$version" >> "$tmp"
   done < <(grep 'module = ' gradle/libs.versions.toml)
   conflicts=$(awk '{ if ($1 in seen && seen[$1] != $2) printf "  %s: %s vs %s\n", $1, seen[$1], $2; seen[$1] = $2 }' "$tmp")
   rm -f "$tmp"
   if [ -n "$conflicts" ]; then
      echo "single-source: same module declared with different versions:"
      echo "$conflicts"
      return 1
   fi
   # The Kotlin Gradle plugin (buildSrc classpath) and the Kotlin plugins
   # (main build classpath) must be the exact same version.
   local kgp_ref plugin_ref
   kgp_ref=$(grep 'kotlin-gradle-plugin' gradle/libs.versions.toml | sed -E 's/.*version\.ref = "([^"]+)".*/\1/')
   plugin_ref=$(grep '^kotlin-jvm' gradle/libs.versions.toml | sed -E 's/.*version\.ref = "([^"]+)".*/\1/')
   if [ -z "$kgp_ref" ] || [ "$kgp_ref" != "$plugin_ref" ]; then
      echo "single-source: kotlin-gradle-plugin and the kotlin-jvm plugin do not share one version (refs: '$kgp_ref' vs '$plugin_ref')"
      return 1
   fi
   echo "single-source: all external coordinates come from gradle/libs.versions.toml (kotlin $(toml_version_value kotlin))"
}

# ---------------------------------------------------------------------------
# Gate 3: locks
# ---------------------------------------------------------------------------
gate_locks() {
   local missing=0 m
   for m in "${ALL_MODULES[@]}" buildSrc; do
      if [ ! -s "$m/gradle.lockfile" ]; then
         echo "locks: missing lock file $m/gradle.lockfile (run 'bash verify.sh --prime')"
         missing=1
      fi
   done
   if [ ! -s settings-gradle.lockfile ]; then
      echo "locks: missing lock file settings-gradle.lockfile (run 'bash verify.sh --prime')"
      missing=1
   fi
   [ "$missing" -eq 0 ] || return 1
   # Strict, read-only, offline resolution of every configuration in the tree:
   # fails on missing lock state, on mismatches and on extra entries.
   if ! gradle_verify verifyLockedResolution; then
      echo "locks: strict locked resolution failed (lock files are missing, stale or incomplete)"
      return 1
   fi
}

# ---------------------------------------------------------------------------
# Gate 4: offline-build
# ---------------------------------------------------------------------------
gate_offline_build() {
   local tasks=() m
   for m in "${MODULES[@]}"; do
      tasks+=(":$m:testClasses")
   done
   if ! gradle_verify "${tasks[@]}"; then
      echo "offline-build: compilation failed under --offline"
      return 1
   fi
   local checks=()
   for m in "${MODULES[@]}"; do
      checks+=(":$m:verifyNoForbiddenDeps")
   done
   if ! gradle_verify "${checks[@]}"; then
      echo "offline-build: a forbidden dependency group was resolved"
      return 1
   fi
}

# ---------------------------------------------------------------------------
# Gate 5: offline-test
# ---------------------------------------------------------------------------
count_tests() {
   local dir="$1/build/test-results/test" total skipped
   total=$(grep -ho 'tests="[0-9]*"' "$dir"/TEST-*.xml 2>/dev/null | grep -oE '[0-9]+' | awk '{s+=$1} END{print s+0}')
   skipped=$(grep -ho 'skipped="[0-9]*"' "$dir"/TEST-*.xml 2>/dev/null | grep -oE '[0-9]+' | awk '{s+=$1} END{print s+0}')
   echo $((total - skipped))
}

gate_offline_test() {
   local m tasks=()
   for m in "${MODULES[@]}"; do
      rm -rf "$m/build/test-results/test" "$m/build/reports/tests"
      tasks+=(":$m:test")
   done
   if ! gradle_verify -Pverify.excludeContainerTests "${tasks[@]}"; then
      echo "offline-test: test run failed under --offline"
      return 1
   fi
   local n
   for m in "${MODULES[@]}"; do
      n=$(count_tests "$m")
      echo "tests :$m=$n"
      if [ "$n" -eq 0 ]; then
         echo "offline-test: $m executed 0 tests"
         return 1
      fi
   done
}

# ---------------------------------------------------------------------------
# Gate 6: examples
# ---------------------------------------------------------------------------
gate_examples() {
   if grep -q '<hoplite.version>1.0.7</hoplite.version>' example-maven/maven.pom \
      && grep -q '<kotlin.version>1.3.50</kotlin.version>' example-maven/maven.pom; then
      echo "examples: example-maven EXCLUDED - maven.pom pins published com.sksamuel.hoplite:1.0.7 and kotlin 1.3.50 from Maven Central, so building it validates released artifacts, not this checkout"
   else
      echo "examples: example-maven no longer pins hoplite 1.0.7 / kotlin 1.3.50 - the exclusion reason is stale, re-evaluate this gate"
      return 1
   fi
   if grep -qE 'com\.sksamuel\.hoplite:hoplite-(core|yaml):_' example-native/build.gradle.kts; then
      echo "examples: example-native EXCLUDED - build.gradle.kts depends on com.sksamuel.hoplite:hoplite-core:_ / hoplite-yaml:_ (unresolvable '_' version placeholders) and requires a GraalVM native-image toolchain that verify.sh does not provision"
   else
      echo "examples: example-native version placeholders are gone - the exclusion reason is stale, re-evaluate this gate"
      return 1
   fi
}

# ---------------------------------------------------------------------------
# Gate 7: clean-tree
# ---------------------------------------------------------------------------
gate_clean_tree() {
   local after
   after=$(git status --porcelain)
   if [ "$after" != "$TREE_SNAPSHOT_BEFORE" ]; then
      echo "clean-tree: the verification run modified the working tree:"
      diff <(printf '%s\n' "$TREE_SNAPSHOT_BEFORE") <(printf '%s\n' "$after") || true
      return 1
   fi
}

# ---------------------------------------------------------------------------
# Prime (networked preparation, no conclusions)
# ---------------------------------------------------------------------------
cmd_prime() {
   echo "==> prime: locating JDK $EXPECTED_JDK_MAJOR"
   local jdk
   if jdk=$(find_jdk "$EXPECTED_JDK_MAJOR"); then
      echo "prime: found JDK $EXPECTED_JDK_MAJOR at $jdk"
   else
      install_jdk "$EXPECTED_JDK_MAJOR"
      jdk=$(find_jdk "$EXPECTED_JDK_MAJOR") || { echo "prime: JDK $EXPECTED_JDK_MAJOR installation failed"; exit 1; }
   fi
   export JAVA_HOME="$jdk"
   echo "prime: JAVA_HOME=$JAVA_HOME"

   echo "==> prime: warming the Gradle wrapper"
   gradle_prime --version >/dev/null

   echo "==> prime: resolving every configuration and writing dependency lock files"
   gradle_prime -Pverify.locks resolveAndLockAll --write-locks

   echo "==> prime: compiling the verified modules (warms dependency and transform caches)"
   local tasks=() m
   for m in "${MODULES[@]}"; do
      tasks+=(":$m:testClasses")
   done
   gradle_prime -Pverify.locks "${tasks[@]}"

   echo "prime: done - dependencies cached, lock files written; no verification verdict was produced"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
run_gate() {
   local name="$1"
   shift
   echo "==> $name"
   if "$@"; then
      echo "[OK] $name"
   else
      echo "[FAIL] $name"
      echo "VERIFY FAILED: $name"
      exit 1
   fi
}

if [ "${1:-}" = "--prime" ]; then
   cmd_prime
   exit 0
fi

if [ $# -gt 0 ]; then
   echo "usage: bash verify.sh [--prime]" >&2
   exit 2
fi

TREE_SNAPSHOT_BEFORE=$(git status --porcelain)

run_gate toolchain gate_toolchain
run_gate single-source gate_single_source
run_gate locks gate_locks
run_gate offline-build gate_offline_build
run_gate offline-test gate_offline_test
run_gate examples gate_examples
run_gate clean-tree gate_clean_tree

echo "VERIFY OK"
