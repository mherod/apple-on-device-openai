import Combine
import Foundation
import SwiftUI

// MARK: - Probe Definition

struct CapabilityProbe: Identifiable, Sendable {
    let id = UUID()
    let category: String
    let prompt: String
    let validator: @Sendable (String) -> Bool
}

// MARK: - Probe Status

enum ProbeStatus: Equatable {
    case pending
    case running
    case passed(String)
    case failed(String)
    case error(String)

    static func == (lhs: ProbeStatus, rhs: ProbeStatus) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending), (.running, .running): return true
        case (.passed(let a), .passed(let b)): return a == b
        case (.failed(let a), .failed(let b)): return a == b
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }

    var icon: String {
        switch self {
        case .pending: return "circle"
        case .running: return "arrow.trianglehead.clockwise"
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .secondary
        case .running: return .blue
        case .passed: return .green
        case .failed: return .red
        case .error: return .orange
        }
    }

    var preview: String? {
        switch self {
        case .passed(let s), .failed(let s), .error(let s): return s
        default: return nil
        }
    }
}

// MARK: - Test Runner

@MainActor
final class CapabilityTestRunner: ObservableObject {
    struct Result: Identifiable {
        let id: UUID
        let probe: CapabilityProbe
        var status: ProbeStatus
    }

    @Published var results: [Result] = []
    @Published var isRunning = false

    var passCount: Int { results.filter { if case .passed = $0.status { return true }; return false }.count }
    var totalCount: Int { results.count }

    static let probes: [CapabilityProbe] = [
        CapabilityProbe(
            category: "Reasoning",
            prompt: "A bat and a ball cost $1.10. The bat costs $1 more than the ball. How much does the ball cost?",
            validator: { r in r.contains("0.05") || r.lowercased().contains("5 cents") }
        ),
        CapabilityProbe(
            category: "Swift Code",
            prompt: "Write a Swift function that returns the nth Fibonacci number iteratively.",
            validator: { r in r.contains("func") && r.lowercased().contains("fibonacci") }
        ),
        CapabilityProbe(
            category: "Summarisation",
            prompt: """
                Summarise in 2 sentences: The transformer architecture, introduced in \
                'Attention is All You Need' (2017), replaced recurrent networks with \
                self-attention mechanisms, enabling parallelisation and leading to \
                breakthroughs like BERT and GPT.
                """,
            validator: { r in !r.isEmpty && r.count < 600 }
        ),
        CapabilityProbe(
            category: "Creative Writing",
            prompt: "Write a haiku about on-device AI.",
            validator: { r in
                r.components(separatedBy: "\n")
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    .count >= 2
            }
        ),
        CapabilityProbe(
            category: "Multilingual",
            prompt: "Translate 'The quick brown fox jumps over the lazy dog' into French, Spanish, and Japanese.",
            validator: { r in
                r.unicodeScalars.contains { $0.value >= 0x3000 && $0.value <= 0x9FFF }
            }
        ),
        CapabilityProbe(
            category: "Math",
            prompt: "What is 17 × 23 + 144 ÷ 12? Show your working.",
            validator: { r in r.contains("403") }
        ),
        CapabilityProbe(
            category: "Role-play",
            prompt: "You are a pirate. Respond only in pirate speak. What is the capital of France?",
            validator: { r in
                let l = r.lowercased()
                return l.contains("paris") &&
                    (l.contains("arr") || l.contains("ahoy") || l.contains("matey") ||
                     l.contains("ye") || l.contains("cap"))
            }
        ),
        CapabilityProbe(
            category: "Instruction Following",
            prompt: "List exactly 5 programming languages, one per line, no numbering, no extra text.",
            validator: { r in
                r.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .count == 5
            }
        ),
        CapabilityProbe(
            category: "Common Sense",
            prompt: "I put an ice cube in a sealed thermos. After 2 hours in a warm room, what state is it in and why?",
            validator: { r in
                let l = r.lowercased()
                return l.contains("liquid") || l.contains("water") || l.contains("melt")
            }
        ),
        CapabilityProbe(
            category: "Self-awareness",
            prompt: "What model are you, and what are your limitations compared to a large cloud-based model?",
            validator: { r in !r.isEmpty }
        ),
    ]

    func run(port: Int) async {
        isRunning = true
        results = Self.probes.map { Result(id: $0.id, probe: $0, status: .pending) }

        for i in results.indices {
            results[i].status = .running
            do {
                let response = try await query(prompt: results[i].probe.prompt, port: port)
                let passed = results[i].probe.validator(response)
                let preview = String(response.prefix(120)).replacingOccurrences(of: "\n", with: " ")
                results[i].status = passed ? .passed(preview) : .failed(preview)
            } catch {
                results[i].status = .error(error.localizedDescription)
            }
        }

        isRunning = false
    }

    private func query(prompt: String, port: Int) async throws -> String {
        let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "apple-on-device",
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 300,
        ])
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        return message?["content"] as? String ?? ""
    }
}
