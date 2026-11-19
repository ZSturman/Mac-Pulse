import Foundation
import Darwin

// Executed with the same App Sandbox entitlement as the widget. This checks
// API access, not WidgetKit hosting, rendering, scheduling, or deep links.
let sampler = SystemSampler()
_ = sampler.sample(includeDisk: false)
Thread.sleep(forTimeInterval: 0.5)
let snapshot = sampler.sample(includeDisk: false)
guard let cpu = snapshot.cpu, (0...100).contains(cpu.total),
      let memory = snapshot.memory, memory.total > 0, memory.used <= memory.total,
      memory.pressure != .unknown, snapshot.swapUsed != nil else {
    fputs("FAIL: sandboxed aggregate CPU, memory, pressure, or swap could not be read.\n", stderr)
    exit(1)
}
print("PASS: aggregate CPU, memory, pressure, and swap are readable with the widget's App Sandbox entitlement.")
