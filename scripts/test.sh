#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p build
xcrun swiftc MacPulse/Core/Metrics.swift MacPulse/Core/SystemSampler.swift \
  MacPulse/App/ProcessSampler.swift MacPulse/App/ProcessRanking.swift MacPulse/App/Alerts.swift Tests/main.swift -o build/CoreChecks
build/CoreChecks
