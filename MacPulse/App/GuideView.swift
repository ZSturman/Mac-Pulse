import SwiftUI

struct GuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A little context goes a long way.").font(.system(size: 27, weight: .semibold, design: .rounded))
                    Text("Use these signals together to understand what your Mac is doing.").foregroundStyle(.secondary)
                }.padding(.vertical, 8)
                guideCard("CPU · how busy your processor is", icon: "cpu", color: .mint,
                          text: "The dashboard shows the percentage of all logical cores in use. User is work done by apps; system is work done by macOS. Short spikes are normal. If usage stays high while you are doing very little, check Processes, sorted by CPU.")
                guideCard("Memory pressure · the signal to watch", icon: "memorychip", color: .purple,
                          text: "macOS uses spare RAM to keep things fast, so high memory use alone is not a problem. Normal pressure means it is managing comfortably. Elevated or high pressure means it is working harder to reclaim memory. If the Mac also feels slow, save your work and close apps you no longer need.")
                guideCard("App, wired, compressed, and swap", icon: "square.stack.3d.up", color: .blue,
                          text: "App memory is anonymous RAM excluding purgeable pages. Wired memory must remain in RAM. Compressed memory is RAM packed by macOS to make space. These make up memory used. File cache is reclaimable and excluded. Swap is disk space used as extra memory; it can remain allocated after pressure has passed.")
                guideCard("Desktop widget · a recent snapshot", icon: "rectangle.3.group", color: .orange,
                          text: "Right-click your desktop → Edit Widgets → Mac Pulse. Choose a small, medium, or large widget and place it on your desktop or in Notification Center. The widget samples independently, even with the app closed. Check its sample time: macOS schedules refreshes and may delay them. Click the widget to open the live dashboard.")
                guideCard("A lightweight, private window into your Mac", icon: "lock.shield", color: .green,
                          text: "All readings come from this Mac. There are no accounts, network requests, cleanup actions, or process termination controls. Graph history lives in memory for five minutes and clears on quit. Closing the window keeps monitoring and alerts running; the menu bar item appears when something needs attention, and quitting stops app sampling. Settings lets you change alerts, the menu bar, and the update interval.")
            }.padding(26).frame(maxWidth: 1000)
        }
    }

    private func guideCard(_ title: String, icon: String, color: Color, text: String) -> some View {
        PulseCard {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: icon).font(.title2).foregroundStyle(color).frame(width: 30)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.headline)
                    Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                }
            }
        }
    }
}
