import SwiftUI
import EasyTierShared

private enum LogFile: String, CaseIterable, Identifiable {
    case daemon
    case core

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daemon: return "easytierd.log"
        case .core: return "core.log"
        }
    }

    var exportFilename: String {
        switch self {
        case .daemon: return "easytierd.log"
        case .core: return "easytier-core.log"
        }
    }
}

struct LogView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("logPreservedLines") private var logPreservedLines: Int = 1000
    @Namespace private var bottomID
    @State private var selectedLog: LogFile = .daemon
    @State private var lineLimit = 300
    @State private var logContent: [LogLine] = []
    @State private var errorMessage: TextItem?
    @State private var isWatching = false
    @State private var isRefreshing = false
    @State private var watchTask: Task<Void, Never>?
    @State private var scrollToBottomRequest = 0
    @State private var wasWatchingBeforeBackground = false
#if os(iOS)
    @State private var exportURL: URL?
    @State private var isExportPresented = false
#endif
    @State private var exportErrorMessage: TextItem?
    private let client = JailbreakIPCClient()
    
    var body: some View {
        CompatNavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Picker("log", selection: $selectedLog) {
                    ForEach(LogFile.allCases) { log in
                        Text(log.title).tag(log)
                    }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                Picker("lines", selection: $lineLimit) {
                    Text("200").tag(200)
                    Text("300").tag(300)
                    Text("500").tag(500)
                    Text("1000").tag(1000)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                ScrollView {
                    ScrollViewReader { proxy in
                        LazyVStack(alignment: .leading) {
                            if logContent.isEmpty {
                                Text("No log lines.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.top, 32)
                            }
                            ForEach(logContent) { line in
                                logLineView(line.text)
                            }
                            Text("").id(bottomID)
                        }
                        .padding()
                        .onChange(of: scrollToBottomRequest) { _ in
                            withAnimation {
                                proxy.scrollTo(bottomID, anchor: .bottom)
                            }
                        }
                    }
                }
#if os(iOS)
                .background(Color(UIColor.systemGroupedBackground))
#endif
            }
            .navigationTitle("logging")
            .adaptiveNavigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: ToolbarLeading) {
                    Button(action: {
                        logContent = []
                    }) {
                        Image(systemName: "trash")
                    }.tint(.red)
                }
                ToolbarItem(placement: ToolbarTrailing) {
                    Button(action: {
                        presentExport()
                    }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: ToolbarTrailing) {
                    Button(action: {
                        if isWatching {
                            stopWatchingLog()
                        } else {
                            startWatchingLog(fromStart: false)
                        }
                    }) {
                        Image(systemName: isWatching ? "pause" : "play")
                    }
                }
                ToolbarItem(placement: ToolbarTrailing) {
                    Button(action: {
                        Task { await refreshLog() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isRefreshing)
                }
                ToolbarItem(placement: ToolbarTrailing) {
                    Button(action: {
                        scrollToBottomRequest += 1
                    }) {
                        Image(systemName: "arrow.down.to.line.compact")
                    }
                }
            }
        }
        .onAppear {
            if !isWatching {
                startWatchingLog(fromStart: true)
            }
        }
        .onDisappear {
            stopWatchingLog()
            wasWatchingBeforeBackground = false
        }
        .onChange(of: selectedLog) { _ in
            startWatchingLog(fromStart: true)
        }
        .onChange(of: lineLimit) { _ in
            Task { await refreshLog() }
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                if wasWatchingBeforeBackground {
                    startWatchingLog(fromStart: false)
                    wasWatchingBeforeBackground = false
                }
            case .inactive, .background:
                wasWatchingBeforeBackground = isWatching
                stopWatchingLog()
            @unknown default:
                break
            }
        }
        .alert(item: $errorMessage) { msg in
            Alert(title: Text("common.error"), message: Text(msg.text))
        }
        .alert(item: $exportErrorMessage) { msg in
            Alert(title: Text("common.error"), message: Text(msg.text))
        }
#if os(iOS)
        .sheet(isPresented: $isExportPresented) {
            if let url = exportURL {
                ShareSheet(activityItems: [url])
            }
        }
#endif
    }

    private func startWatchingLog(fromStart: Bool) {
        watchTask?.cancel()
        if fromStart {
            logContent = []
        }
        isWatching = true
        watchTask = Task {
            await refreshLog()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await refreshLog()
            }
        }
    }

    private func stopWatchingLog() {
        watchTask?.cancel()
        watchTask = nil
        isWatching = false
    }

    @MainActor
    private func refreshLog() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let limit = min(logPreservedLines, lineLimit)
            let lines = try await client.tailLog(limit: limit, log: selectedLog.rawValue)
            if lines != logContent.map(\.text) {
                logContent = lines.map { LogLine(text: $0) }
            }
        } catch {
            errorMessage = .init(error.localizedDescription)
        }
    }

    @ViewBuilder
    private func logLineView(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(logLineForeground(text))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 1)
            .padding(.horizontal, 4)
            .background(logLineBackground(text))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func logLineForeground(_ text: String) -> Color {
        if text.contains(" ERROR ") || text.localizedCaseInsensitiveContains("failed") {
            return .red
        }
        if text.contains(" WARN ") || text.localizedCaseInsensitiveContains("warning") {
            return .orange
        }
        if text.contains(" DEBUG ") || text.contains(" TRACE ") {
            return .secondary
        }
        return .primary
    }

    private func logLineBackground(_ text: String) -> Color {
        if text.contains(" ERROR ") || text.localizedCaseInsensitiveContains("failed") {
            return Color.red.opacity(0.12)
        }
        if text.contains(" WARN ") || text.localizedCaseInsensitiveContains("warning") {
            return Color.orange.opacity(0.10)
        }
        return Color.clear
    }

    private func presentExport() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(selectedLog.exportFilename)
        let text = logContent.map(\.text).joined(separator: "\n")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            exportErrorMessage = .init(error.localizedDescription)
            return
        }
#if os(iOS)
        exportURL = url
        isExportPresented = true
#elseif os(macOS)
        do {
            try saveExportedFileToDisk(url, suggestedName: selectedLog.exportFilename)
        } catch {
            exportErrorMessage = .init(error.localizedDescription)
        }
#endif
    }
}

#if DEBUG && compiler(>=5.9)
#Preview("Log") {
    LogView()
}
#endif
