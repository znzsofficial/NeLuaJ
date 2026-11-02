# Bundled binary inventory and maintenance

These are checked-in binaries, not Maven dependencies. A filename, namespace or
hash does **not** establish an upstream release, license or ABI guarantee. None
of these JARs contains a manifest or Maven `pom.properties` identifying its
version. Exact upstream versions and reproducible source/build recipes are
currently unknown; do not substitute a similarly named upstream artifact.

## Inventory (SHA-256)

| Path | Bytes | SHA-256 |
| --- | ---: | --- |
| `app/libs/IconDrawable.jar` | 2,397 | `bb870397dca9d0ca8270bbbb9a09558c9d5fcc71febf025e0414f11110caeb9d` |
| `app/libs/luajpp_nocglib.jar` | 581,164 | `1f9a89b40319f84627074ff0324436cbb19dd2be67014e88858d566c89b9d355` |
| `app/libs/textfield.jar` | 15,605 | `83d22527abb758f68da98c82fd4d675a19e9135cb06146dc3cdeab00a6fd8b71` |
| `tests/libs/luajpp.jar` (test-only) | 352,841 | `f14aad3eca93a871250276eddbed8565ea6bca91adc77eabe6100947cfca4d75` |

Known local provenance, not verified upstream attribution:

- `IconDrawable.jar`: contains `vinx.graphics.IconDrawable` and its Kotlin
  companion; first added in repository commit `b7e0f18`. Upstream source,
  version and binary-specific license evidence have not been recorded.
- `textfield.jar`: contains `vinx.material.textfield.MaterialTextField` and its
  Kotlin companion; also first added in `b7e0f18`. Upstream source, version and
  binary-specific license evidence have not been recorded.
- `luajpp_nocglib.jar`: the legacy Luaj++/AndroLua runtime, containing
  `org.luaj`, `com.androlua`, `com.luajava` and `com.myopicmobile` classes. First
  added under this name in `2bd89b9`. The name alone does not document what was
  stripped or how it was built. Exact upstream revision and artifact-specific
  licensing/source provenance remain unverified.
- `tests/libs/luajpp.jar`: commit `1e51873` records a JSE-only trim of the full
  JAR previously taken from the sibling `NeLuaJ+Builder` repository: LuaJ core,
  LuaC and JSE classes retained, Android-side classes removed. No exact builder
  source revision or reproducible trimming recipe was recorded. This JAR is
  only a behavioral-test dependency, not the Android runtime dependency.

## Runtime source takeover gate

`app/build.gradle.kts` has one `runtimeTakeoverClasses` registry covering
`LuaString`, `LuaUtf8String` and the in-tree JSE bridge/platform replacements.
`filteredLuajppJar` removes the exact top-level class and all `$` nested classes
for every registered family. Some registered bridge classes are already absent
from the original nocglib JAR; keeping them registered protects future updates.

`./gradlew :app:verifyRuntimeTakeover` checks that each registered family has a
same-path Java/Kotlin source file, that source/JAR class-family collisions are
registered, and that the actual filtered JAR contains exactly the original
class entries minus registered families. It runs through `preBuild` and `check`
as well as explicitly in CI. This is a source-layout/archive consistency check,
**not** compiled ABI verification, behavioral equivalence or proof that every
possible generated Kotlin class has been enumerated. The existing Java source
and manifest inherited by user-built APKs remain additive-only.

## Updating a binary deliberately

1. Record its trusted origin URL, upstream commit/tag, license evidence and build
   or extraction command. Preserve unknowns rather than guessing a version.
2. Inspect the class inventory (`jar tf <file>`) and compare it with the old
   binary. Review runtime source takeovers before replacing the JAR; update the
   registry if needed. Do not remove source API merely to make compilation pass.
3. Recompute hashes and byte counts and update this inventory. PowerShell:
   `Get-FileHash app/libs/*.jar,tests/libs/*.jar -Algorithm SHA256`; Ubuntu:
   `sha256sum app/libs/*.jar tests/libs/*.jar`.
4. Run `pwsh -File tests/run_tests.ps1` (auto-discovers every `Test*.lua`,
   including `TestLayoutTools`; device-only `bench_override.lua` is not matched).
   `tests/build_maintenance_bootstrap.lua` adds the asset directory to Lua's
   `package.path` before each suite, so real modules required by loadfile-based
   fixtures resolve consistently. `pwsh -File tests/check_build_maintenance.ps1`
   checks runner discovery, this bootstrap, syntax and failure propagation in an
   isolated temporary project with the real JDK; CI runs it on Ubuntu too.
   Run `./gradlew :app:verifyRuntimeTakeover :app:testDebugUnitTest
   :app:assembleDebug :app:assembleRelease`. Existing JVM verification disabling
   for the legacy runtime remains in place; it is not a runtime safety guarantee.
5. Perform device regressions for runtime/interop, dynamic loading and affected
   UI paths. Desktop Lua tests use a different test JAR and cannot prove Android
   runtime compatibility. Preserve minSdk 26 compatibility (e.g. no Java
   `Stream.toList()` assumptions).

## Version maintenance

Normal configuration, tests and debug/release assembly do not write
`app/version.properties`. To increment the code intentionally, run
`./gradlew :app:bumpVersionCode` **alone**, inspect/commit that deliberate change,
then build in a separate Gradle invocation. Combining it with another requested
task is rejected because Android reads the version during configuration. The
existing timestamp-based version name/APK naming remains unchanged; this is not
a reproducible-build claim. CI still retains the existing debug-key-signed
release artifact policy, not production release signing.
