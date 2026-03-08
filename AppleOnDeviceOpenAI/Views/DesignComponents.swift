import SwiftUI

// MARK: - Pulsing Status Orb

struct PulsingOrb: View {
    let isRunning: Bool
    let isChecking: Bool
    @State private var ring = false

    private var color: Color {
        isRunning ? .green : isChecking ? .orange : Color(.tertiaryLabelColor)
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(color.opacity(0.35), lineWidth: 5)
                .frame(width: 34, height: 34)
                .scaleEffect(ring ? 1.6 : 1.0)
                .opacity(ring ? 0 : 0.9)
                .animation(
                    isRunning
                        ? .easeOut(duration: 1.5).repeatForever(autoreverses: false)
                        : .default,
                    value: ring
                )
            Circle()
                .fill(color)
                .frame(width: 20, height: 20)
                .shadow(color: color.opacity(isRunning ? 0.5 : 0), radius: 5)
        }
        .frame(width: 34, height: 34)
        .onAppear { ring = isRunning }
        .onChange(of: isRunning) { _, newVal in ring = newVal }
    }
}

// MARK: - HTTP Method Badge

struct MethodBadge: View {
    let method: String

    var body: some View {
        Text(method)
            .font(.system(.caption2, design: .monospaced, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(color.opacity(0.2), lineWidth: 1))
            .frame(minWidth: 42)
    }

    private var color: Color {
        switch method {
        case "GET":    return .green
        case "POST":   return .blue
        case "PUT":    return .orange
        case "DELETE": return .red
        default:       return .gray
        }
    }
}

// MARK: - Copy Button

struct CopyButton: View {
    let text: String
    let onCopy: () -> Void
    @State private var copied = false

    var body: some View {
        Button {
            onCopy()
            withAnimation(.easeInOut(duration: 0.15)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { copied = false }
            }
        } label: {
            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .foregroundStyle(copied ? Color.green : Color.accentColor)
        }
        .buttonStyle(.borderless)
    }
}
