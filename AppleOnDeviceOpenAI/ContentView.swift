//
//  ContentView.swift
//  AppleOnDeviceOpenAI
//
//  Created by Channing Dai on 6/15/25.
//

import Combine
import SwiftUI
import Foundation
import Network

// MARK: - Models
struct ServerConfiguration {
    var host: String
    var port: Int

    static let `default` = ServerConfiguration(
        host: "127.0.0.1",
        port: 11535
    )

    var url: String {
        "http://\(host):\(port)"
    }

    var openaiBaseURL: String {
        "\(url)/v1"
    }

    var chatCompletionsEndpoint: String {
        "\(url)/v1/chat/completions"
    }
}

// MARK: - ViewModel
@MainActor
class ServerViewModel: ObservableObject {
    @Published var configuration = ServerConfiguration.default
    @Published var hostInput: String = "127.0.0.1"
    @Published var portInput: String = "11535"
    @Published var isModelAvailable: Bool = false
    @Published var modelUnavailableReason: String?
    @Published var isCheckingModel: Bool = false

    @Published var availableAddresses: [String] = []
    @Published var selectedAddress: String = "127.0.0.1" {
        didSet { hostInput = selectedAddress }
    }

    private let serverManager = VaporServerManager()

    var isRunning: Bool {
        serverManager.isRunning
    }

    var lastError: String? {
        serverManager.lastError
    }

    /// True whenever the user is binding to something other than 127.0.0.1.
    var needsLANWarning: Bool {
        // Treat “all interfaces” (0.0.0.0) as LAN‑visible too.
        selectedAddress != "127.0.0.1"
    }

    private var advertisedHost: String {
        switch configuration.host {
        case "0.0.0.0":
            // We are listening on *all* interfaces – pick something shareable
            return primaryLANAddress() ?? "127.0.0.1"
        default:
            // The user chose a concrete IP (loop‑back included)
            return configuration.host
        }
    }

    var serverURL: String {
        "http://\(advertisedHost):\(configuration.port)"
    }

    var openaiBaseURL: String {
        "\(serverURL)/v1"
    }

    var chatCompletionsEndpoint: String {
        "\(serverURL)/v1/chat/completions"
    }

    let modelName = "apple-on-device"

    init() {
        refreshAddresses()                              // populate the picker
        selectedAddress = configuration.host

        // Initialize with current configuration values
        self.hostInput = configuration.host
        self.portInput = String(configuration.port)

        // Check model availability and auto-start server on launch
        Task {
            await startServer()
        }
    }

    func checkModelAvailability() async {
        isCheckingModel = true

        let result = await aiManager.isModelAvailable()

        isModelAvailable = result.available
        modelUnavailableReason = result.reason
        isCheckingModel = false
    }

    func startServer() async {
        // Check model availability before starting
        await checkModelAvailability()

        guard isModelAvailable else {
            return
        }

        updateConfiguration()
        await serverManager.startServer(configuration: configuration)
    }

    func stopServer() async {
        await serverManager.stopServer()
    }

    private func updateConfiguration() {
        configuration.host = selectedAddress

        if let port = Int(portInput.trimmingCharacters(in: .whitespacesAndNewlines)),
            port > 0 && port <= 65535
        {
            configuration.port = port
        }
    }

    func resetToDefaults() {
        configuration = ServerConfiguration.default
        selectedAddress = configuration.host
        hostInput = configuration.host
        portInput = String(configuration.port)
    }

    func copyToClipboard(_ text: String) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    /// Refresh the list (e.g. when a new Wi‑Fi network is joined).
    func refreshAddresses() {
        // Put localhost first, keep “all interfaces”, then the rest.
        availableAddresses = ["127.0.0.1", "0.0.0.0"]
            + currentIPv4Addresses().filter { $0 != "127.0.0.1" }
        // Keep selection valid
        if !availableAddresses.contains(selectedAddress) {
            selectedAddress = availableAddresses.first ?? "0.0.0.0"
        }
    }

    /// Returns all IPv4 addresses currently assigned to the device,
    /// sorted and deduplicated (loop‑back first).
    func currentIPv4Addresses() -> [String] {
        var addresses: Set<String> = []

        var addrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrPointer) == 0 else { return [] }
        defer { freeifaddrs(addrPointer) }

        var ptr = addrPointer
        while let iface = ptr?.pointee {
            if iface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var addr = iface.ifa_addr.pointee
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(
                    &addr,
                    socklen_t(iface.ifa_addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                addresses.insert(String(cString: hostname))
            }
            ptr = iface.ifa_next
        }

        // Keep loop‑back first, then alphabetical
        return ["127.0.0.1"] + addresses.subtracting(["127.0.0.1"]).sorted()
    }

    /// Return the first non‑loop‑back IPv4 address that is *not* link‑local (169.254.x.x).
    /// Falls back to nil when no such address exists.
    private func primaryLANAddress() -> String? {
        for addr in currentIPv4Addresses() {
            if addr != "127.0.0.1" && !addr.hasPrefix("169.254") {
                return addr          // Wi‑Fi / Ethernet / USB‑C / Thunderbolt, etc.
            }
        }
        return nil
    }
}

// MARK: - Design Helpers

private struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
    }
}

private struct SectionLabel: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Main View
struct ContentView: View {
    @StateObject private var viewModel = ServerViewModel()
    @StateObject private var testRunner = CapabilityTestRunner()
    @State private var isStarting = false
    @State private var isStopping = false
    @State private var quickStartTab: QuickStartLanguage = .python

    enum QuickStartLanguage: String, CaseIterable {
        case python = "Python"
        case javascript = "JavaScript"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                HStack(spacing: 14) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(viewModel.isRunning ? Color.green : Color.secondary)
                        .frame(width: 48, height: 48)
                        .background(.regularMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Apple On-Device API")
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                        Text("OpenAI-compatible · Local · Private")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if viewModel.isRunning {
                        Label("Live", systemImage: "circle.fill")
                            .font(.system(.caption, weight: .medium))
                            .foregroundStyle(Color.green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    }
                }

                // Server Status
                Card {
                    VStack(spacing: 14) {
                        SectionLabel(title: "Server Status")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 12) {
                            PulsingOrb(isRunning: viewModel.isRunning, isChecking: viewModel.isCheckingModel)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(viewModel.isRunning ? "Running" : viewModel.isCheckingModel ? "Starting…" : "Stopped")
                                    .font(.system(.headline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(viewModel.isRunning ? Color.green : viewModel.isCheckingModel ? Color.orange : Color.secondary)
                            }
                            Spacer()
                            if viewModel.isRunning {
                                Text(viewModel.modelName)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.blue.opacity(0.2), lineWidth: 1))
                                    .foregroundStyle(Color.blue)
                            }
                        }

                        // Model Availability Status
                        HStack {
                            Text("Apple Intelligence:")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            if viewModel.isCheckingModel {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Checking...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            } else {
                                Circle()
                                    .fill(viewModel.isModelAvailable ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)

                                Text(viewModel.isModelAvailable ? "Available" : "Not Available")
                                    .font(.subheadline)
                                    .foregroundColor(viewModel.isModelAvailable ? .green : .orange)
                            }

                            Spacer()

                            if !viewModel.isModelAvailable && !viewModel.isCheckingModel {
                                Button("Retry") {
                                    Task {
                                        await viewModel.checkModelAvailability()
                                    }
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
                        }

                        // Model unavailable reason
                        if !viewModel.isModelAvailable,
                            let reason = viewModel.modelUnavailableReason
                        {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Issue:")
                                    .font(.caption)
                                    .foregroundColor(.orange)

                                Text(reason)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color.orange.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }

                        if let error = viewModel.lastError {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Error:")
                                    .font(.caption)
                                    .foregroundColor(.red)

                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color.red.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }

                        HStack {
                            if viewModel.isRunning {
                                Button("Stop Server") {
                                    Task {
                                        isStopping = true
                                        await viewModel.stopServer()
                                        isStopping = false
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(isStopping)
                                .tint(.red)
                            } else {
                                Button(
                                    viewModel.isModelAvailable
                                        ? "Start Server" : "Model Not Available"
                                ) {
                                    Task {
                                        isStarting = true
                                        await viewModel.startServer()
                                        isStarting = false
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(
                                    isStarting || !viewModel.isModelAvailable
                                        || viewModel.isCheckingModel
                                )
                                .tint(viewModel.isModelAvailable ? .green : .gray)
                            }

                            if isStarting || isStopping {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                }

                // OpenAI API Integration - Only show when running
                if viewModel.isRunning {
                    GroupBox("OpenAI API Integration") {
                        VStack(spacing: 16) {
                            // Base URL for OpenAI clients
                            APIEndpointRow(
                                title: "Base URL",
                                subtitle: "For OpenAI Python/JavaScript clients",
                                url: viewModel.openaiBaseURL,
                                onCopy: { viewModel.copyToClipboard(viewModel.openaiBaseURL) }
                            )

                            Divider()

                            // Chat Completions Endpoint
                            APIEndpointRow(
                                title: "Chat Completions",
                                subtitle: "Direct API endpoint",
                                url: viewModel.chatCompletionsEndpoint,
                                onCopy: {
                                    viewModel.copyToClipboard(viewModel.chatCompletionsEndpoint)
                                }
                            )

                            Divider()

                            // Model Name
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Model Name")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text("Use this in your API requests")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                HStack {
                                    Text(viewModel.modelName)
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)

                                    Button("Copy") {
                                        viewModel.copyToClipboard(viewModel.modelName)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                    // Quick Start Examples
                    GroupBox("Quick Start") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Language", selection: $quickStartTab) {
                                ForEach(QuickStartLanguage.allCases, id: \.self) { lang in
                                    Text(lang.rawValue).tag(lang)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            let pythonCode = """
                                from openai import OpenAI

                                client = OpenAI(
                                    base_url="\(viewModel.openaiBaseURL)",
                                    api_key=""
                                )

                                response = client.chat.completions.create(
                                    model="\(viewModel.modelName)",
                                    messages=[{"role": "user", "content": "Hello!"}]
                                )
                                """

                            let jsCode = """
                                import OpenAI from "openai";

                                const client = new OpenAI({
                                    baseURL: "\(viewModel.openaiBaseURL)",
                                    apiKey: "",
                                });

                                const response = await client.chat.completions.create({
                                    model: "\(viewModel.modelName)",
                                    messages: [{ role: "user", content: "Hello!" }],
                                });
                                """

                            CodeBlock(
                                code: quickStartTab == .python ? pythonCode : jsCode,
                                onCopy: {
                                    viewModel.copyToClipboard(quickStartTab == .python ? pythonCode : jsCode)
                                })
                        }
                    }
                }

                // Server Configuration
                GroupBox("Server Configuration") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Picker("Bind Address", selection: $viewModel.selectedAddress) {
                                ForEach(viewModel.availableAddresses, id: \.self) { addr in
                                    Text(addr == "0.0.0.0" ? "All interfaces (0.0.0.0)" : addr).tag(addr)
                                }
                            }
                            .pickerStyle(.menu)
                            .disabled(viewModel.isRunning)

                            Button {
                                viewModel.refreshAddresses()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .imageScale(.medium)      // optional: size the symbol
                            }
                            .help("Rescan network interfaces")
                            .disabled(viewModel.isRunning)
                        }

                        // LAN‑visibility warning
                        if viewModel.needsLANWarning {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text("Binding to this address makes the server reachable by other devices\n" +
                                     "on your local network. Make sure you trust the network or use a firewall.")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                            }
                        }

                        HStack {
                            Text("Port:")
                                .frame(width: 60, alignment: .leading)
                            TextField("11535", text: $viewModel.portInput)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .disabled(viewModel.isRunning)
                        }

                        HStack {
                            Spacer()
                            Button("Reset to Defaults") {
                                viewModel.resetToDefaults()
                            }
                            .buttonStyle(.borderless)
                            .disabled(viewModel.isRunning)
                        }
                    }
                }

                // Capability test probe runner
                if viewModel.isRunning {
                    CapabilityTestSection(runner: testRunner, port: viewModel.configuration.port)
                }

                // Available endpoints - More compact version
                if viewModel.isRunning {
                    GroupBox("All Available Endpoints") {
                        VStack(alignment: .leading, spacing: 8) {
                            EndpointRow(method: "GET", path: "/health", description: "Health check")
                            EndpointRow(method: "GET", path: "/status", description: "Model status")
                            EndpointRow(
                                method: "GET", path: "/v1/models", description: "List models")
                            EndpointRow(
                                method: "POST", path: "/v1/chat/completions",
                                description: "Chat completions")
                        }
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: 600)
    }
}

// MARK: - Helper Views
struct APIEndpointRow: View {
    let title: String
    let subtitle: String
    let url: String
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(.subheadline, weight: .medium))
                    Text(subtitle).font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                CopyButton(text: url, onCopy: onCopy)
            }
            Text(url)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        }
    }
}

struct CodeBlock: View {
    let code: String
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(Color(.textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
            CopyButton(text: code, onCopy: onCopy)
        }
    }
}

struct EndpointRow: View {
    let method: String
    let path: String
    let description: String

    var body: some View {
        HStack(spacing: 10) {
            MethodBadge(method: method)
            Text(path)
                .font(.system(.footnote, design: .monospaced))
            Spacer()
            Text(description)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Capability Test Section

struct CapabilityTestSection: View {
    @ObservedObject var runner: CapabilityTestRunner
    let port: Int

    var body: some View {
        GroupBox("Capability Tests") {
            VStack(spacing: 12) {
                HStack {
                    if !runner.results.isEmpty {
                        Text("\(runner.passCount)/\(runner.totalCount) passed")
                            .font(.subheadline)
                            .foregroundColor(runner.passCount == runner.totalCount ? .green : .orange)
                    } else {
                        Text("Run probes to evaluate model capabilities")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(runner.isRunning ? "Running…" : runner.results.isEmpty ? "Run Tests" : "Re-run") {
                        Task { await runner.run(port: port) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(runner.isRunning)
                }

                if !runner.results.isEmpty {
                    Divider()
                    ForEach(runner.results) { result in
                        ProbeRow(result: result)
                    }
                }
            }
        }
    }
}

struct ProbeRow: View {
    let result: CapabilityTestRunner.Result

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: result.status.icon)
                .foregroundColor(result.status.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.probe.category)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let preview = result.status.preview {
                    Text(preview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
    }
}

#Preview {
    ContentView()
}
