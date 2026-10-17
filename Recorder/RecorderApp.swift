import SwiftUI

@main
struct RecorderApp: App {
    @StateObject private var log = CaptureLog()

    var body: some Scene {
        WindowGroup("e-Fatura Recorder") {
            VStack(spacing: 0) {
                RecorderWebView(log: log)
                HStack {
                    Text("Captured: \(log.count)")
                    Spacer()
                    Text(log.fileURL.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .frame(minWidth: 1100, minHeight: 800)
        }
    }
}
