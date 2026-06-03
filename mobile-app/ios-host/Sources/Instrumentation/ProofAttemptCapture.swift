// Instrumentation — matches test-kit/measurement/event-spec.md so the Mac
// tester gets identical events. Adapted from capture-ios.swift.snippet.
import Foundation
import os.log
import UIKit

struct ProofAttemptEvent: Codable {
    let type: String
    let timestamp: TimeInterval        // unix ms
    let attemptId: String
    let platform: String
    let mode: String
    let appState: String
    let hackVariant: String
    let deviceOs: String
    let osVersion: String
    let appVersion: String
    let anonId: String
    let payload: [String: AnyCodableValue]
}

final class ProofAttemptCapture {
    static let shared = ProofAttemptCapture()
    private var current: AttemptContext?
    private let log = Logger(subsystem: "xyz.rep.host", category: "proof-attempt")

    private lazy var anonId: String = {
        if let id = UserDefaults.standard.string(forKey: "rep.anonId") { return id }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: "rep.anonId")
        return new
    }()

    func startAttempt(platform: String, mode: String, appState: String, hackVariant: String) {
        current = AttemptContext(
            attemptId: UUID().uuidString, platform: platform, mode: mode,
            appState: appState, hackVariant: hackVariant,
            startTimestamp: Date().timeIntervalSince1970 * 1000
        )
        emit(type: "start", payload: ["entryScreen": .string("main")])
    }

    func emit(type: String, payload: [String: AnyCodableValue] = [:]) {
        guard let ctx = current else { log.error("emit without attempt: \(type)"); return }
        let event = ProofAttemptEvent(
            type: type, timestamp: Date().timeIntervalSince1970 * 1000,
            attemptId: ctx.attemptId, platform: ctx.platform, mode: ctx.mode,
            appState: ctx.appState, hackVariant: ctx.hackVariant, deviceOs: "iOS",
            osVersion: UIDevice.current.systemVersion,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            anonId: anonId, payload: payload
        )
        Task { await persist(event) }
        log.debug("\(type) ms=\(Int(event.timestamp - ctx.startTimestamp))")
    }

    /// ms since this attempt started (for `msSince*` fields / wall-clock).
    func elapsedMs() -> Double {
        guard let ctx = current else { return 0 }
        return Date().timeIntervalSince1970 * 1000 - ctx.startTimestamp
    }

    func endAttempt() { current = nil }

    private func persist(_ event: ProofAttemptEvent) async {
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("proof-attempts.jsonl")
        guard let data = try? JSONEncoder().encode(event),
              let line = String(data: data, encoding: .utf8) else { return }
        let entry = (line + "\n").data(using: .utf8)!
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile(); handle.write(entry); handle.closeFile()
        } else {
            try? entry.write(to: file)
        }
    }
}

private struct AttemptContext {
    let attemptId: String
    let platform: String
    let mode: String
    let appState: String
    let hackVariant: String
    let startTimestamp: TimeInterval
}

enum AnyCodableValue: Codable {
    case string(String), int(Int), double(Double), bool(Bool)
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        }
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        throw DecodingError.typeMismatch(AnyCodableValue.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Unknown type"))
    }
}
