#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
"$project_dir/scripts/build.sh"
install_dir="$HOME/Applications"
destination="$install_dir/Auto Clicker.app"
mkdir -p "$install_dir"
# Stop only this app before replacing its executable.
existing_pid="$(pgrep -f '^.*/Auto Clicker.app/Contents/MacOS/AutoClicker$' || true)"
if [[ -n "$existing_pid" ]]; then
    for app_pid in ${(f)existing_pid}; do kill -TERM "$app_pid"; done
    for attempt in {1..30}; do
        if ! pgrep -f '^.*/Auto Clicker.app/Contents/MacOS/AutoClicker$' >/dev/null; then break; fi
        sleep 0.1
    done
    if pgrep -f '^.*/Auto Clicker.app/Contents/MacOS/AutoClicker$' >/dev/null; then
        printf 'Auto Clicker is still closing. Try installing again.\n' >&2
        exit 1
    fi
fi
ditto "$project_dir/build/Auto Clicker.app" "$destination"
codesign --verify --strict "$destination"
open "$destination"
printf 'Installed and opened: %s\n' "$destination"
