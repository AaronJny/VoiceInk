import AppKit
import SwiftUI

struct LocalEnhancementServiceManagementView: View {
    @EnvironmentObject private var aiService: AIService

    @State private var isOllamaExpanded = false
    @State private var isLocalCLIExpanded = false
    @AppStorage("ollamaSettingsLastViewedServerID") private var lastViewedOllamaServerID = ""
    @State private var selectedOllamaServerID: UUID?
    @State private var ollamaServerName = ""
    @State private var ollamaBaseURL = OllamaService.defaultBaseURL
    @State private var ollamaUserRefreshError: String?
    @State private var isSyncingOllamaState = false
    @State private var ollamaServerBeingRefreshed: UUID?
    @State private var ollamaServerPendingRemoval: OllamaServerConfiguration?
    @State private var localCLICommandTemplate = ""
    @State private var localCLITimeoutSeconds = LocalCLIService.defaultTimeoutSeconds
    @State private var isSyncingLocalCLIState = false

    private var isLocalCLIConfigured: Bool {
        !localCLICommandTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProviderSectionHeader(
                title: "Local Enhancement Services",
                subtitle: "Connect Ollama or configure a CLI command for local enhancement."
            )
            .padding(.top, 8)

            VStack(spacing: 0) {
                LocalProviderDisclosureRow(
                    title: Text(verbatim: "Ollama"),
                    subtitle: Text("Server"),
                    systemImage: "server.rack",
                    statusTitle: ollamaStatusTitle,
                    isExpanded: $isOllamaExpanded
                ) {
                    ollamaConfiguration
                }

                Divider()
                    .padding(.leading, 58)

                LocalProviderDisclosureRow(
                    title: Text("CLI Provider"),
                    subtitle: Text("Claude, Codex, scripts, or any command"),
                    systemImage: "terminal",
                    statusTitle: isLocalCLIConfigured ? Text("Configured") : Text("Not configured"),
                    isExpanded: $isLocalCLIExpanded
                ) {
                    localCLIConfiguration
                }
            }
            .background(AppMaterialCardBackground(cornerRadius: 11))
        }
        .onAppear {
            selectedOllamaServerID = OllamaServerConfiguration.editorSelection(
                savedID: UUID(uuidString: lastViewedOllamaServerID),
                defaultID: aiService.defaultOllamaServerID,
                servers: ollamaServers
            )
            syncOllamaStateFromSelection()
            syncLocalCLIStateFromService()
        }
        .confirmationDialog(
            "Remove Ollama Server?",
            isPresented: Binding(
                get: { ollamaServerPendingRemoval != nil },
                set: { if !$0 { ollamaServerPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                removePendingOllamaServer()
            }
            Button("Cancel", role: .cancel) {
                ollamaServerPendingRemoval = nil
            }
        } message: {
            if let server = ollamaServerPendingRemoval {
                Text("Remove \(server.name) from VoiceInk? Your Ollama server and models will not be deleted.")
            }
        }
    }

    private var ollamaServers: [OllamaServerConfiguration] {
        aiService.ollamaServers
    }

    private var selectedOllamaServer: OllamaServerConfiguration? {
        aiService.ollamaServerConfiguration(id: selectedOllamaServerID)
    }

    private var ollamaModelNames: [String] {
        aiService.availableOllamaModels(serverID: selectedOllamaServerID)
    }

    // Read the saved value directly. A second @State copy can show a stale/empty
    // model after a server refresh or when this settings view is recreated.
    private var ollamaModelBinding: Binding<String> {
        OllamaModelComboBox.savedModelBinding(aiService: aiService, serverID: selectedOllamaServerID)
    }

    private var ollamaStatusTitle: Text {
        if ollamaServerBeingRefreshed != nil || aiService.isOllamaRefreshing
            || ollamaServers.contains(where: { aiService.ollamaServerStatus(id: $0.id).isRefreshing })
        {
            return Text("Checking")
        }

        let connectedCount = ollamaServers.filter {
            aiService.ollamaServerStatus(id: $0.id).isConnected
        }.count
        if connectedCount > 0 {
            return Text("Connected")
        }

        return ollamaServers.isEmpty ? Text("Not configured") : Text("Disconnected")
    }

    private var ollamaActionTitle: LocalizedStringKey {
        guard let selectedOllamaServer else { return "Connect" }
        return aiService.ollamaServerStatus(id: selectedOllamaServer.id).isConnected ? "Refresh" : "Connect"
    }

    private var selectedOllamaServerIsRefreshing: Bool {
        guard let selectedOllamaServer else { return false }
        return ollamaServerBeingRefreshed == selectedOllamaServer.id
            || aiService.ollamaServerStatus(id: selectedOllamaServer.id).isRefreshing
    }

    private var ollamaConfiguration: some View {
        LocalProviderExpandedContent {
            if ollamaServers.isEmpty {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Not configured")
                            .font(.system(size: 12, weight: .medium))
                        Text("Add a server to use local models in Modes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        addOllamaServer()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                LocalProviderFormRow(title: "Server") {
                    HStack(spacing: 8) {
                        Picker("Server", selection: $selectedOllamaServerID) {
                            ForEach(ollamaServers) { server in
                                Text(server.name).tag(server.id as UUID?)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: 240, alignment: .leading)
                        .onChange(of: selectedOllamaServerID) { _, newValue in
                            lastViewedOllamaServerID = newValue?.uuidString ?? ""
                            syncOllamaStateFromSelection()
                        }

                        Button {
                            addOllamaServer()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .help("Add Ollama server")
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(role: .destructive) {
                            ollamaServerPendingRemoval = selectedOllamaServer
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("Remove Ollama server")
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                Divider()
                    .padding(.leading, LocalProviderMetrics.labelWidth + 12)

                LocalProviderFormRow(title: "Name") {
                    TextField("Server name", text: $ollamaServerName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                        .onSubmit { saveSelectedOllamaServer() }
                }

                LocalProviderFormRow(title: "URL") {
                    HStack(spacing: 8) {
                        TextField("", text: $ollamaBaseURL, prompt: Text(verbatim: "http://localhost:11434"))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 320)
                            .disabled(selectedOllamaServerIsRefreshing)
                            .onChange(of: ollamaBaseURL) { _, _ in ollamaUserRefreshError = nil }
                            .onSubmit { checkOllamaConnectionFromUserAction() }

                        Button {
                            ollamaUserRefreshError = nil
                            checkOllamaConnectionFromUserAction()
                        } label: {
                            if selectedOllamaServerIsRefreshing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text(ollamaActionTitle)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(selectedOllamaServerIsRefreshing)
                    }
                }

                if let ollamaUserRefreshError {
                    Text(ollamaUserRefreshError)
                        .font(.caption)
                        .foregroundStyle(AppTheme.Status.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, LocalProviderMetrics.labelWidth + 12)
                }

                LocalProviderFormRow(title: "Default") {
                    if selectedOllamaServerID == aiService.defaultOllamaServerID {
                        Label("Default", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Default") {
                            if let selectedOllamaServerID {
                                aiService.setDefaultOllamaServer(id: selectedOllamaServerID)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                Divider()
                    .padding(.leading, LocalProviderMetrics.labelWidth + 12)

                LocalProviderFormRow(title: "Model") {
                    OllamaModelComboBox(model: ollamaModelBinding, modelNames: ollamaModelNames)
                        .frame(maxWidth: 320)
                }
            }
        }
    }

    private var localCLIConfiguration: some View {
        LocalProviderExpandedContent {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Command")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Menu {
                        ForEach(LocalCLITemplate.allCases) { template in
                            Button(template.displayName) {
                                aiService.loadLocalCLITemplate(template)
                                syncLocalCLIStateFromService()
                            }
                        }
                    } label: {
                        Label("Template", systemImage: "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                TextEditor(text: $localCLICommandTemplate)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 88)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppTheme.Border.control.opacity(0.4), lineWidth: 1)
                    )
                    .onChange(of: localCLICommandTemplate) { _, newValue in
                        guard !isSyncingLocalCLIState else { return }
                        aiService.updateLocalCLICommandTemplate(newValue)
                    }
            }

            Divider()
                .padding(.leading, LocalProviderMetrics.labelWidth + 12)

            LocalProviderFormRow(title: "Timeout") {
                Picker("Timeout", selection: $localCLITimeoutSeconds) {
                    Text("15s").tag(15.0)
                    Text("30s").tag(30.0)
                    Text("45s").tag(45.0)
                    Text("60s").tag(60.0)
                    Text("90s").tag(90.0)
                    Text("120s").tag(120.0)
                    Text("180s").tag(180.0)
                    Text("300s").tag(300.0)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 110, alignment: .leading)
                .onChange(of: localCLITimeoutSeconds) { _, newValue in
                    aiService.updateLocalCLITimeoutSeconds(newValue)
                }
            }

            Text("Variables: VOICEINK_SYSTEM_PROMPT, VOICEINK_USER_PROMPT, VOICEINK_FULL_PROMPT")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private func checkOllamaConnectionFromUserAction() {
        guard let serverID = selectedOllamaServerID else { return }
        saveSelectedOllamaServer()
        ollamaServerBeingRefreshed = serverID

        Task { @MainActor in
            defer {
                if ollamaServerBeingRefreshed == serverID {
                    ollamaServerBeingRefreshed = nil
                }
            }
            let result = await aiService.refreshOllamaServer(id: serverID)
            guard selectedOllamaServerID == serverID else { return }

            ollamaUserRefreshError = result.errorMessage


        }
    }

    private func addOllamaServer() {
        let serverNumber = ollamaServers.count + 1
        let server = aiService.addOllamaServer(
            name: String(localized: "Ollama Server \(serverNumber)"),
            baseURL: OllamaService.defaultBaseURL
        )
        selectedOllamaServerID = server.id
        ollamaUserRefreshError = nil
        syncOllamaStateFromSelection()
    }

    private func removePendingOllamaServer() {
        guard let server = ollamaServerPendingRemoval else { return }

        aiService.removeOllamaServer(id: server.id)
        ollamaServerPendingRemoval = nil
        selectedOllamaServerID = aiService.defaultOllamaServerID ?? ollamaServers.first?.id
        ollamaUserRefreshError = nil
        syncOllamaStateFromSelection()
    }

    private func syncOllamaStateFromSelection() {
        guard let server = selectedOllamaServer else {
            isSyncingOllamaState = true
            ollamaServerName = ""
            ollamaBaseURL = OllamaService.defaultBaseURL
            DispatchQueue.main.async {
                isSyncingOllamaState = false
            }
            return
        }

        isSyncingOllamaState = true
        if selectedOllamaServerID != server.id {
            selectedOllamaServerID = server.id
        }
        ollamaServerName = server.name
        ollamaBaseURL = server.baseURL
        ollamaUserRefreshError = aiService.ollamaServerStatus(id: server.id).errorMessage
        DispatchQueue.main.async {
            isSyncingOllamaState = false
        }
    }

    private func saveSelectedOllamaServer() {
        guard !isSyncingOllamaState, var server = selectedOllamaServer else { return }

        let name = ollamaServerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = ollamaBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { server.name = name }
        if !baseURL.isEmpty { server.baseURL = baseURL }
        aiService.updateOllamaServer(server)
    }

    private func syncLocalCLIStateFromService() {
        isSyncingLocalCLIState = true
        localCLICommandTemplate = aiService.localCLICommandTemplate
        localCLITimeoutSeconds = aiService.localCLITimeoutSeconds
        DispatchQueue.main.async {
            isSyncingLocalCLIState = false
        }
    }
}

private enum LocalProviderMetrics {
    static let labelWidth: CGFloat = 72
}

private struct LocalProviderDisclosureRow<Content: View>: View {
    let title: Text
    let subtitle: Text
    let systemImage: String
    let statusTitle: Text
    @Binding var isExpanded: Bool
    let content: () -> Content

    init(
        title: Text,
        subtitle: Text,
        systemImage: String,
        statusTitle: Text,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.statusTitle = statusTitle
        self._isExpanded = isExpanded
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.smooth(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(AppTheme.Surface.control)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(AppTheme.Border.control.opacity(0.3), lineWidth: 1)
                                )
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        title
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)

                        subtitle
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 12)

                    statusTitle
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.leading, 58)

                content()
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
        }
    }
}

private struct LocalProviderExpandedContent<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LocalProviderFormRow<Content: View>: View {
    let title: LocalizedStringKey
    let content: () -> Content

    init(title: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: LocalProviderMetrics.labelWidth, alignment: .leading)

            content()

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


/// One native editable dropdown, with one arrow and one persistence path for
/// menu selection and typed model names. Updating the control never writes back.
struct OllamaModelComboBox: NSViewRepresentable {
    @Binding var model: String
    let modelNames: [String]

    static func savedModelBinding(aiService: AIService, serverID: UUID?) -> Binding<String> {
        Binding(
            get: { aiService.ollamaServerConfiguration(id: serverID)?.preferredModel ?? "" },
            set: { value in
                guard let serverID else { return }
                aiService.setPreferredOllamaModel(
                    value.trimmingCharacters(in: .whitespacesAndNewlines), serverID: serverID)
            }
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: $model) }

    func makeNSView(context: Context) -> NSComboBox {
        Self.makeControl(coordinator: context.coordinator)
    }

    static func makeControl(coordinator: Coordinator) -> NSComboBox {
        let control = NSComboBox()
        control.isEditable = true
        control.completes = false
        control.placeholderString = String(localized: "Model name")
        control.setAccessibilityLabel(String(localized: "Model"))
        control.setAccessibilityIdentifier("ollamaModelComboBox")
        control.delegate = coordinator
        return control
    }

    func updateNSView(_ control: NSComboBox, context: Context) {
        context.coordinator.model = $model
        Self.updateControl(control, model: model, modelNames: modelNames,
                           coordinator: context.coordinator)
    }

    static func updateControl(_ control: NSComboBox, model: String, modelNames: [String],
                              coordinator: Coordinator) {
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }
        if control.objectValues.compactMap({ $0 as? String }) != modelNames {
            control.removeAllItems()
            control.addItems(withObjectValues: modelNames)
        }
        if control.stringValue != model { control.stringValue = model }
    }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var model: Binding<String>
        var isUpdating = false

        init(model: Binding<String>) { self.model = model }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard !isUpdating, let control = notification.object as? NSComboBox,
                  let selected = control.objectValueOfSelectedItem as? String else { return }
            model.wrappedValue = selected
        }

        func controlTextDidChange(_ notification: Notification) {
            guard !isUpdating, let control = notification.object as? NSComboBox else { return }
            model.wrappedValue = control.stringValue
        }
    }
}
