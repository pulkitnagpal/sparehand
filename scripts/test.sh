#!/bin/zsh
# swift-testing ships with the Command Line Tools but isn't on swift test's default search path.
set -e
cd "${0:A:h}/.."
CLT=/Library/Developer/CommandLineTools/Library/Developer
if [[ "$(xcode-select -p)" == *CommandLineTools* ]]; then
  exec swift test -Xswiftc -F -Xswiftc $CLT/Frameworks -Xlinker -F -Xlinker $CLT/Frameworks \
    -Xlinker -rpath -Xlinker $CLT/Frameworks -Xlinker -rpath -Xlinker $CLT/usr/lib "$@"
fi
exec swift test "$@"
