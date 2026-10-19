#!/bin/sh
# 在只有 Command Line Tools 的机器上跑 JisiKit 单元测试（Swift Testing）。装了 Xcode 后直接 `swift test` 即可。
set -e
cd "$(dirname "$0")/../JisiKit"
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
if [ -d "$F/Testing.framework" ] && ! xcode-select -p | grep -q Xcode.app; then
  exec swift test -Xswiftc -DJISI_NO_SWIFTDATA -Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L "$@"
fi
exec swift test "$@"
