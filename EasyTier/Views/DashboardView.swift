import SwiftUI
import Combine
import os
import TOMLKit
import UniformTypeIdentifiers
import EasyTierShared
#if os(iOS)
import UIKit
#endif

private let dashboardLogger = Logger(subsystem: APP_BUNDLE_ID, category: "main.dashboard")
private let autoSaveInterval: UInt64 = 1_200_000_000

#if os(iOS)
private struct AutoFocusTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusToken: Int
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.placeholder = placeholder
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.returnKeyType = .done
        textField.delegate = context.coordinator
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged(_:)),
            for: .editingChanged
        )
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.parent = self
        if textField.text != text {
            textField.text = text
        }
        textField.placeholder = placeholder
        guard context.coordinator.focusToken != focusToken else { return }
        context.coordinator.focusToken = focusToken
        DispatchQueue.main.async {
            textField.becomeFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AutoFocusTextField
        var focusToken = -1

        init(parent: AutoFocusTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            parent.onSubmit()
            return true
        }
    }
}
#endif

struct DashboardView<Manager: TunnelManagerProtocol>: View {
    @Environment(\.scenePhase) var scenePhase
    @ObservedObject var manager: Manager
    @ObservedObject var selectedSession: SelectedProfileSession
    
    @AppStorage("selectedProfileName") var lastSelected: String?
    
    @State var currentProfile = NetworkProfile()
    @State var isLocalPending = false

    @State var showManageSheet = false

    @State var showNewNetworkSheet = false
    @State var newNetworkInput = ""
    @State var showEditConfigNameSheet = false
    @State var editConfigNameInput = ""
    @State var editingProfileName: String?
    @State private var createFocusToken = 0
    @State private var renameFocusToken = 0

    @State var showImportPicker = false
#if os(iOS)
    @State var exportURL: IdentifiableURL?
#endif
    @State var showEditSheet = false
    @State var editText = ""

    @State var errorMessage: TextItem?
    @State var showConflictAlert = false
    @State var conflictConfigName: String?
    @State var conflictDetails: String = ""

    @State private var autoSaveTask: Task<Void, Never>? = nil
    
    init(manager: Manager, selectedSession: SelectedProfileSession) {
        _manager = ObservedObject(wrappedValue: manager)
        _selectedSession = ObservedObject(wrappedValue: selectedSession)
    }

    struct ProfileEntry: Identifiable, Equatable {
        var id: String { configName }
        var configName: String
        var profile: NetworkProfile?
    }

    var isConnected: Bool {
        manager.status.isConnected
    }
    var isPending: Bool {
        isLocalPending || manager.status.isPending
    }
    var hasSelectedProfile: Bool {
        selectedSession.session != nil
    }

    var mainView: some View {
        Group {
            if hasSelectedProfile {
                if isConnected {
                    StatusView(currentProfile.networkName, manager: manager)
                } else {
                    NetworkEditView(profile: $currentProfile)
                        .disabled(isPending)
                }
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "xmark.circle")
                        .resizable()
                        .frame(width: 64, height: 64)
                        .foregroundStyle(Color.accentColor)
                    Text("no_network_selected")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
#if os(iOS)
                .background(Color(.systemGroupedBackground))
#endif
            }
        }
    }

    func createProfile() {
        let baseName = newNetworkInput.isEmpty ? String(localized: "new_network") : newNetworkInput
        guard let sanitizedName = availableConfigName(baseName) else { return }
        let profile = NetworkProfile()
        Task { @MainActor in
            do {
                try ProfileStore.save(profile, named: sanitizedName)
                selectedSession.session = try await ProfileStore.openSession(named: sanitizedName)
                newNetworkInput = ""
                showNewNetworkSheet = false
            } catch {
                dashboardLogger.error("create profile failed: \(error)")
                errorMessage = .init(error.localizedDescription)
            }
        }
    }

    var manageSheet: some View {
        CompatNavigationStack {
            Form {
                Section("network") {
                    let profiles = ProfileStore.loadIndexOrEmpty().map { IdenticalTextItem($0) }
                    ForEach(profiles) { item in
                        HStack {
                            Text(item.id)
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedSession.session?.name == item.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {  
                            if selectedSession.session?.name == item.id {
                                Task { @MainActor in
                                    await closeSelectedSession()
                                }
                            } else {
                                Task { @MainActor in
                                    await loadProfile(item.id)
                                }
                            }
                        }
                        .contextMenu {
                            Button {
                                beginConfigNameEdit(item.id)
                            } label: {
                                Label("rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                Task { @MainActor in
                                    do {
                                        if selectedSession.session?.name == item.id {
                                            await closeSelectedSession(save: false)
                                        }
                                        try ProfileStore.deleteProfile(named: item.id)
                                    } catch {
                                        dashboardLogger.error("delete profile failed: \(error)")
                                        errorMessage = .init(error.localizedDescription)
                                    }
                                }
                            } label: {
                                Label("delete", systemImage: "trash")
                                    .tint(.red)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                beginConfigNameEdit(item.id)
                            } label: {
                                Label("rename", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
                    .onDelete { indexSet in
                        withAnimation {
                            for index in indexSet {
                                Task { @MainActor in
                                    do {
                                        if selectedSession.session?.name == profiles[index].id {
                                            await closeSelectedSession(save: false)
                                        }
                                        try ProfileStore.deleteProfile(named: profiles[index].id)
                                    } catch {
                                        dashboardLogger.error("delete profile failed: \(error)")
                                        errorMessage = .init(error.localizedDescription)
                                    }
                                }
                            }
                        }
                    }
                }
                Section("device.management") {
                    Button {
                        beginProfileCreate()
                    } label: {
                        HStack(spacing: 12) {
                            if #available(iOS 18.0, *) {
                                Image(systemName: "document.badge.plus")
                            } else {
                                Image(systemName: "plus.app")
                            }
                            Text("profile.create_network")
                        }
                    }
#if os(macOS)
                    .buttonStyle(.borderless)
                    .tint(.accentColor)
#endif
                    Button {
                        presentEditInText()
                    } label: {
                        HStack(spacing: 12) {
                            if #available(iOS 18.4, *) {
                                Image(systemName: "long.text.page.and.pencil")
                            } else {
                                Image(systemName: "square.and.pencil")
                            }
                            Text("profile.edit_in_text")
                        }
                    }
#if os(macOS)
                    .buttonStyle(.borderless)
                    .tint(.accentColor)
#endif
                    Button {
                        showImportPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            if #available(iOS 18.0, *) {
                                Image(systemName: "arrow.down.document")
                            } else {
                                Image(systemName: "square.and.arrow.down")
                            }
                            Text("profile.import_config")
                        }
                    }
#if os(macOS)
                    .buttonStyle(.borderless)
                    .tint(.accentColor)
#endif
                    Button {
                        exportSelectedProfile()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.up")
                            Text("profile.export_config")
                        }
                    }
#if os(macOS)
                    .buttonStyle(.borderless)
                    .tint(.accentColor)
#endif
                }
            }
            .adaptiveGroupedFormStyle()
            .navigationTitle("device.management")
            .adaptiveNavigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showManageSheet = false
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .sheet(isPresented: $showNewNetworkSheet) {
                createProfileSheet
            }
            .sheet(isPresented: $showEditConfigNameSheet) {
                editConfigNameSheet
            }
        }
    }

    var createProfileSheet: some View {
        CompatNavigationStack {
            Form {
                Section("add_new_network") {
#if os(iOS)
                    AutoFocusTextField(
                        text: $newNetworkInput,
                        placeholder: String(localized: "config_name"),
                        focusToken: createFocusToken,
                        onSubmit: createProfile
                    )
#else
                    TextField("config_name", text: $newNetworkInput)
                        .adaptiveNoTextInputAutocapitalization()
#endif
                }
            }
            .adaptiveGroupedFormStyle()
            .navigationTitle("add_new_network")
            .adaptiveNavigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        showNewNetworkSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("network.create") {
                        createProfile()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .onAppear {
                focusCreateField()
            }
        }
    }

    var editConfigNameSheet: some View {
        CompatNavigationStack {
            Form {
                Section("edit_config_name") {
#if os(iOS)
                    AutoFocusTextField(
                        text: $editConfigNameInput,
                        placeholder: String(localized: "config_name"),
                        focusToken: renameFocusToken,
                        onSubmit: commitConfigNameEdit
                    )
#else
                    TextField("config_name", text: $editConfigNameInput)
                        .adaptiveNoTextInputAutocapitalization()
#endif
                }
            }
            .adaptiveGroupedFormStyle()
            .navigationTitle("edit_config_name")
            .adaptiveNavigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        showEditConfigNameSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save") {
                        commitConfigNameEdit()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .onAppear {
                focusRenameField()
            }
        }
    }

    var body: some View {
        CompatNavigationStack {
            mainView
                .navigationTitle(selectedSession.session?.name ?? String(localized: "select_network"))
                .toolbar {
                    ToolbarItem(placement: ToolbarLeading) {
                    Button {
                        showManageSheet = true
                    } label: {
                        Label("select_network", systemImage: "chevron.up.chevron.down")
                    }
                    .disabled(isPending || isConnected)
                }
                ToolbarItem(placement: ToolbarTrailing) {
                    Button {
                        guard !isPending else { return }
                        isLocalPending = true
                        Task { @MainActor in
                            if isConnected {
                                await manager.disconnect()
                            } else {
                                do {
                                    await saveProfile()
                                    try await manager.connect(profile: currentProfile)
                                } catch {
                                    dashboardLogger.error("connect failed: \(error)")
                                    errorMessage = .init(error.localizedDescription)
                                }
                            }
                            isLocalPending = false
                        }
                    } label: {
                        Label(
                            isConnected ? "connection_disconnect" : "connection_connect",
                            systemImage: isConnected ? "cable.connector.slash" : "cable.connector"
                        )
                        .labelStyle(.titleAndIcon)
                        .padding(10)
                    }
                    .disabled((!hasSelectedProfile && !isConnected) || manager.isLoading || isPending)
#if os(iOS)
                    .buttonStyle(.plain)
#endif
                    .foregroundStyle(isConnected ? Color.red : Color.accentColor)
                    .animation(.interactiveSpring(), value: [isConnected, isPending])
                }
            }
        }
        .onAppear {
            Task { @MainActor in
                if !hasSelectedProfile,
                   let lastSelected {
                    await loadProfile(lastSelected)
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            guard [.inactive, .background].contains(newPhase) else { return }
            Task { @MainActor in
                autoSaveTask?.cancel()
                autoSaveTask = nil
                await saveProfile()
            }
        }
        .onChange(of: selectedSession.session) { session in
            lastSelected = session?.name
        }
        .onChange(of: currentProfile) { profile in
            selectedSession.session?.document.profile = profile
            scheduleAutoSave()
        }
        .onDisappear {
            autoSaveTask?.cancel()
            autoSaveTask = nil
            Task { @MainActor in
                await saveProfile()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .profileDocumentConflictDetected)) { notification in
            let configName = notification.userInfo?["configName"] as? String
            Task { @MainActor in
                handleConflict(configName: configName ?? selectedSession.session?.name)
            }
        }
        .sheet(isPresented: $showManageSheet) {
            manageSheet
                .sheet(isPresented: $showEditSheet) {
                    CompatNavigationStack {
                        VStack(spacing: 0) {
                            TextEditor(text: $editText)
                                .font(.system(.body, design: .monospaced))
                                .padding(8)
                        }
                        .navigationTitle("edit_config")
                        .adaptiveNavigationBarTitleInline()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("common.cancel") {
                                    showEditSheet = false
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("save") {
                                    saveEditInText()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
#if os(iOS)
                .sheet(item: $exportURL) { url in
                    ShareSheet(activityItems: [url.url])
                }
#endif
                .fileImporter(
                    isPresented: $showImportPicker,
                    allowedContentTypes: [
                        UTType(mimeType: "application/toml"),
                        UTType(filenameExtension: "toml"),
                        .plainText
                    ].compactMap { $0 },
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        guard let url = urls.first else { return }
                        importConfig(from: url)
                    case .failure(let error):
                        errorMessage = .init(error.localizedDescription)
                    }
                }
                .alert(item: $errorMessage) { msg in
                    dashboardLogger.error("received error: \(String(describing: msg))")
                    return Alert(title: Text("common.error"), message: Text(msg.text))
                }
        }
        .alert(item: $errorMessage) { msg in
            dashboardLogger.error("received error: \(String(describing: msg))")
            return Alert(title: Text("common.error"), message: Text(msg.text))
        }
        .alert("icloud_conflict_title", isPresented: $showConflictAlert) {
            Button("icloud_conflict_use_local") {
                resolveConflict(useLocal: true)
            }
            Button("icloud_conflict_use_remote") {
                resolveConflict(useLocal: false)
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            if conflictDetails.isEmpty {
                Text("icloud_conflict_message")
            } else {
                Text(conflictDetails)
            }
        }
    }
    
    @MainActor
    private func loadProfile(_ named: String) async {
        await closeSelectedSession()
        do {
            let session = try await ProfileStore.openSession(named: named)
            selectedSession.session = session
            currentProfile = session.document.profile
        } catch {
            dashboardLogger.error("load profile failed: \(error)")
            if let conflict = error as? ProfileStoreError,
               case .conflict = conflict {
                handleConflict(configName: named)
            } else {
                errorMessage = .init(error.localizedDescription)
            }
            selectedSession.session = nil
        }
    }
    
    @MainActor
    private func saveProfile() async {
        if let session = selectedSession.session {
            do {
                try await session.save()
            } catch {
                dashboardLogger.error("save failed: \(error)")
                if let conflict = error as? ProfileStoreError,
                   case .conflict = conflict {
                    handleConflict(configName: session.name)
                } else {
                    errorMessage = .init(error.localizedDescription)
                }
            }
        }
    }

    private func focusCreateField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            createFocusToken += 1
        }
    }

    private func focusRenameField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            renameFocusToken += 1
        }
    }

    private func beginProfileCreate() {
        newNetworkInput = ""
        showNewNetworkSheet = true
    }

    private func importConfig(from url: URL) {
        Task { @MainActor in
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let toml = try String(contentsOf: url, encoding: .utf8)
                let config = try TOMLDecoder().decode(NetworkConfig.self, from: toml)
                let rawName = url.deletingPathExtension().lastPathComponent
                guard let configName = availableConfigName(rawName) else { return }
                let profile = NetworkProfile(from: config)
                try ProfileStore.save(profile, named: configName)
                selectedSession.session = try await ProfileStore.openSession(named: configName)
            } catch {
                dashboardLogger.error("import failed: \(error)")
                errorMessage = .init(error.localizedDescription)
            }
        }
    }

    private func exportSelectedProfile() {
        guard let session = selectedSession.session else {
            errorMessage = .init(String(localized: "no_network_selected"))
            return
        }
        let fileURL = try? ProfileStore.fileURL(forConfigName: session.name)
        guard let fileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            errorMessage = .init("Config file not found.")
            return
        }
        dashboardLogger.info("exporting to: \(fileURL)")
#if os(iOS)
        exportURL = .init(fileURL)
#elseif os(macOS)
        do {
            try saveExportedFileToDisk(fileURL)
        } catch {
            errorMessage = .init(error.localizedDescription)
        }
#endif
    }

    private func presentEditInText() {
        Task { @MainActor in
            guard hasSelectedProfile else {
                errorMessage = .init(String(localized: "no_network_selected"))
                return
            }
            do {
                let config = currentProfile.toConfig()
                editText = try TOMLEncoder().encode(config).string ?? ""
                showEditSheet = true
            } catch {
                dashboardLogger.error("edit load failed: \(error)")
                errorMessage = .init(error.localizedDescription)
            }
        }
    }

    private func saveEditInText() {
        Task { @MainActor in
            do {
                let config = try TOMLDecoder().decode(NetworkConfig.self, from: editText)
                currentProfile = NetworkProfile(from: config)
                showEditSheet = false
            } catch {
                dashboardLogger.error("edit save failed: \(error)")
                errorMessage = .init(error.localizedDescription)
            }
        }
    }

    private func beginConfigNameEdit(_ name: String) {
        editingProfileName = name
        editConfigNameInput = name
        showEditConfigNameSheet = true
    }

    private func commitConfigNameEdit() {
        guard let editingProfileName else {
            showEditConfigNameSheet = false
            return
        }
        let trimmed = editConfigNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = .init("Config name cannot be empty.")
            return
        }
        guard trimmed != editingProfileName else {
            showEditConfigNameSheet = false
            return
        }
        guard let sanitizedName = validatedConfigName(trimmed) else { return }
        Task { @MainActor in
            do {
                let renamingSelected = selectedSession.session?.name == editingProfileName
                if renamingSelected {
                    await saveProfile()
                    await closeSelectedSession(save: false)
                }
                try ProfileStore.renameProfileFile(from: editingProfileName, to: sanitizedName)
                if lastSelected == editingProfileName {
                    lastSelected = sanitizedName
                }
                if renamingSelected {
                    await loadProfile(sanitizedName)
                }
                showEditConfigNameSheet = false
                self.editingProfileName = nil
            } catch {
                dashboardLogger.error("rename failed: \(error)")
                errorMessage = .init(error.localizedDescription)
            }
        }
    }

    private func validatedConfigName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = .init("Config name cannot be empty.")
            return nil
        }
        let sanitized = ProfileStore.sanitizedFileName(trimmed, fallback: "")
        guard sanitized == trimmed else {
            errorMessage = .init("Config name contains invalid characters.")
            return nil
        }
        let hasDuplicate = ProfileStore.loadIndexOrEmpty().enumerated().contains { item in
            return item.element.caseInsensitiveCompare(sanitized) == .orderedSame
        }
        guard !hasDuplicate else {
            errorMessage = .init("Config name already exists.")
            return nil
        }
        return sanitized
    }

    private func availableConfigName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = .init("Config name cannot be empty.")
            return nil
        }
        let sanitized = ProfileStore.sanitizedFileName(trimmed, fallback: "")
        guard sanitized == trimmed else {
            errorMessage = .init("Config name contains invalid characters.")
            return nil
        }
        let existingNames = ProfileStore.loadIndexOrEmpty().enumerated().compactMap { item -> String? in
            return item.element
        }
        if !existingNames.contains(where: { $0.caseInsensitiveCompare(sanitized) == .orderedSame }) {
            return sanitized
        }
        var suffix = 2
        while suffix < 10_000 {
            let candidate = "\(sanitized) \(suffix)"
            if !existingNames.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
                return candidate
            }
            suffix += 1
        }
        errorMessage = .init("Config name already exists.")
        return nil
    }

    @MainActor
    private func closeSelectedSession(save: Bool = true) async {
        dashboardLogger.info("closing session with save: \(save)")
        autoSaveTask?.cancel()
        autoSaveTask = nil
        if save {
            await saveProfile()
        }
        if let session = selectedSession.session {
            await session.close()
        }
        selectedSession.session = nil
    }

    private func resolveConflict(useLocal: Bool) {
        Task { @MainActor in
            guard let conflictConfigName else { return }
            do {
                await closeSelectedSession(save: false)
                let url = try ProfileStore.fileURL(forConfigName: conflictConfigName)
                if useLocal {
                    try ProfileStore.resolveConflictUseLocal(at: url)
                } else {
                    try ProfileStore.resolveConflictUseRemote(at: url)
                }
                try await ProfileStore.waitForConflictResolved(at: url)
                await loadProfile(conflictConfigName)
            } catch {
                dashboardLogger.error("resolve conflict failed: \(error)")
                errorMessage = .init(error.localizedDescription)
            }
            self.conflictConfigName = nil
            self.conflictDetails = ""
        }
    }

    @MainActor
    private func handleConflict(configName: String?) {
        guard let configName else { return }
        if showConflictAlert, conflictConfigName == configName {
            return
        }
        conflictConfigName = configName
        conflictDetails = conflictDetailsText(for: configName)
        showConflictAlert = true
    }

    private func conflictDetailsText(for configName: String) -> String {
        guard let url = try? ProfileStore.fileURL(forConfigName: configName) else {
            return String(localized: "icloud_conflict_message")
        }
        let infos = ProfileStore.conflictInfos(at: url)
        guard !infos.isEmpty else {
            return String(localized: "icloud_conflict_message")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let lines = infos.map { info in
            let label = info.local ? String(localized: "local") : String(localized: "icloud")
            let time = info.modificationDate.map { formatter.string(from: $0) } ?? "-"
            let device = info.deviceName ?? "N/A"
            return "\(label): \(device) · \(time)"
        }
        return ([String(localized: "icloud_conflict_message")] + lines).joined(separator: "\n")
    }

    @MainActor
    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        guard selectedSession.session != nil else { return }
        autoSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: autoSaveInterval)
            guard !Task.isCancelled else { return }
            dashboardLogger.info("auto saving...")
            await saveProfile()
        }
    }

}

struct IdentifiableURL: Identifiable {
    var id: URL { self.url }
    var url: URL
    init(_ url: URL) {
        self.url = url
    }
}


#if DEBUG && compiler(>=5.9)
#Preview("Dashboard") {
    let manager = MockTunnelManager()
    let selectedSession = SelectedProfileSession()
    DashboardView(manager: manager, selectedSession: selectedSession)
        .environmentObject(manager)
}
#endif
