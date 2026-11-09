#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/policy-tests
swiftc Sources/Archaive/HotKey.swift Sources/Archaive/ShortcutRecorder.swift Sources/Archaive/System.swift Sources/Archaive/SleepAccess.swift Sources/Archaive/DisplayBrightness.swift Sources/Archaive/PhoneShareHTTP.swift Sources/Archaive/Onboarding.swift Tests/ArchaiveTests/PolicyTests.swift -o .build/policy-tests/check
.build/policy-tests/check
