import EventKit
import Foundation

// MARK: - EventKit wrapper for creating calendar events from document metadata

@MainActor
final class EventKitService {

    static let shared = EventKitService()

    let store = EKEventStore()

    // MARK: - Access

    /// Requests calendar write access (write-only on iOS 17+, full on iOS 16).
    func requestAccess() async -> Bool {
        if #available(iOS 17, *) {
            return (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        } else {
            return await withCheckedContinuation { cont in
                store.requestAccess(to: .event) { granted, _ in
                    cont.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - Event construction

    /// Builds a pre-filled EKEvent from structured document metadata.
    /// Returns nil if no valid date can be parsed.
    func makeEvent(from metadata: StructuredDocumentData, documentTitle: String) -> EKEvent? {
        guard let dateStr = metadata.date else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        guard let baseDate = iso.date(from: dateStr) else { return nil }

        let event = EKEvent(eventStore: store)
        event.calendar = store.defaultCalendarForNewEvents

        // ── Title ─────────────────────────────────────────────────────────────
        switch metadata.documentType {
        case .flight:
            let parts: [String] = [
                metadata.vendor,
                [metadata.origin, metadata.destination].compactMap { $0 }.joined(separator: " → "),
                metadata.flightNumber
            ].compactMap { $0 }.filter { !$0.isEmpty }
            event.title = parts.isEmpty ? documentTitle : parts.joined(separator: " · ")

        case .event:
            event.title = metadata.eventTitle ?? metadata.vendor ?? documentTitle
            if let venue = metadata.vendor, event.title != venue {
                event.location = venue
            }

        default:
            event.title = metadata.vendor ?? documentTitle
        }

        // ── Dates ─────────────────────────────────────────────────────────────
        if let timeStr = metadata.departureTime, let startDate = applyTime(timeStr, to: baseDate) {
            event.startDate = startDate
            if let arrStr = metadata.arrivalTime, let endDate = applyTime(arrStr, to: baseDate) {
                // Handle overnight flights where arrival < departure (next day)
                let endAdjusted = endDate < startDate ? endDate.addingTimeInterval(86400) : endDate
                event.endDate = endAdjusted
            } else {
                event.endDate = startDate.addingTimeInterval(7200) // 2h default
            }
        } else {
            event.isAllDay = true
            event.startDate = baseDate
            event.endDate = baseDate
        }

        // ── Notes ─────────────────────────────────────────────────────────────
        var notes: [String] = []
        if let seat   = metadata.seat          { notes.append("Asiento: \(seat)") }
        if let amount = metadata.formattedAmount { notes.append("Importe: \(amount)") }
        if !notes.isEmpty { event.notes = notes.joined(separator: "\n") }

        return event
    }

    // MARK: - Helpers

    private func applyTime(_ timeStr: String, to date: Date) -> Date? {
        let parts = timeStr.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date)
    }
}
