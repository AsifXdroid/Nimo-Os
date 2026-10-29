#!/bin/bash
# Build the release APK. Proxy -D props are derived from $https_proxy
# at runtime (never written to disk or echoed).
source "$HOME/tools/env.sh"
cd "$HOME/workspace/daily-life-app"
export GRADLE_OPTS=$(python3 -c "
import os, urllib.parse
u = urllib.parse.urlparse(os.environ.get('https_proxy',''))
parts = ['-Xmx768m']
if u.hostname:
    parts += [f'-Dhttp.proxyHost={u.hostname}', f'-Dhttp.proxyPort={u.port}', f'-Dhttps.proxyHost={u.hostname}', f'-Dhttps.proxyPort={u.port}']
    if u.username: parts += [f'-Dhttp.proxyUser={urllib.parse.unquote(u.username)}', f'-Dhttps.proxyUser={urllib.parse.unquote(u.username)}']
    if u.password: parts += [f'-Dhttp.proxyPassword={urllib.parse.unquote(u.password)}', f'-Dhttps.proxyPassword={urllib.parse.unquote(u.password)}']
print(' '.join(parts))")
flutter build apk --release
echo "BUILD_EXIT=$?"
ls -la build/app/outputs/flutter-apk/ 2>/dev/null
