#!/usr/bin/env bash
set -e

echo "==> Enabling core library desugaring in android/app/build.gradle.kts..."
python3 - << 'PYEOF'
path = "android/app/build.gradle.kts"
with open(path) as f:
    content = f.read()

old_compile_options = """    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }"""

new_compile_options = """    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }"""

assert old_compile_options in content, "compileOptions block not found — aborting"
content = content.replace(old_compile_options, new_compile_options)

# Add the desugaring dependency. Insert a dependencies block if none exists,
# right before the closing brace of the `android { ... }` block's sibling area.
if "dependencies {" in content:
    content = content.replace(
        "dependencies {",
        'dependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")',
        1
    )
else:
    content = content.rstrip() + '\n\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")\n}\n'

with open(path, "w") as f:
    f.write(content)
print("Fixed.")
PYEOF

echo "==> flutter clean & pub get..."
flutter clean
flutter pub get

echo "==> Committing and pushing..."
git add .
git commit -m "Enable core library desugaring for flutter_sing_box requirement"
git push

echo "==> Done. Check Actions tab."