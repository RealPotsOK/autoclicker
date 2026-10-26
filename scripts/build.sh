#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_path="$project_dir/build/Auto Clicker.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
if [[ ! -f "$project_dir/Resources/AppIcon.icns" || "$project_dir/scripts/generate-icon.swift" -nt "$project_dir/Resources/AppIcon.icns" ]]; then
    swift "$project_dir/scripts/generate-icon.swift" "$project_dir/build/AppIcon.iconset"
    iconutil -c icns "$project_dir/build/AppIcon.iconset" -o "$project_dir/Resources/AppIcon.icns"
fi
cp "$binary_dir/AutoClicker" "$app_path/Contents/MacOS/AutoClicker"
cp "$project_dir/Resources/Info.plist" "$app_path/Contents/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"
# A stable designated requirement helps macOS retain the app's local permission identity after rebuilding.
codesign --force --sign - --identifier local.kevin.autoclicker \
    --requirements '=designated => identifier "local.kevin.autoclicker"' "$app_path"
codesign --verify --strict "$app_path"
printf 'Built: %s\n' "$app_path"
