import Foundation

// MARK: - Structured data extracted from a document by the LLM

struct StructuredDocumentData: Codable, Equatable {

    // MARK: - Document type

    enum DocumentType: String, Codable, CaseIterable {
        case invoice     = "factura"
        case receipt     = "recibo"
        case contract    = "contrato"
        case payslip     = "nómina"
        case statement   = "extracto"
        case ticket      = "ticket"
        case budget      = "presupuesto"
        case flight      = "vuelo"
        case event       = "evento"
        case other       = "otro"

        var displayName: String {
            switch self {
            case .invoice:   return "Factura"
            case .receipt:   return "Recibo"
            case .contract:  return "Contrato"
            case .payslip:   return "Nómina"
            case .statement: return "Extracto"
            case .ticket:    return "Ticket"
            case .budget:    return "Presupuesto"
            case .flight:    return "Vuelo"
            case .event:     return "Entrada"
            case .other:     return "Documento"
            }
        }

        var systemImage: String {
            switch self {
            case .invoice:   return "doc.text.fill"
            case .receipt:   return "receipt.fill"
            case .contract:  return "doc.badge.gearshape.fill"
            case .payslip:   return "eurosign.circle.fill"
            case .statement: return "list.bullet.rectangle.fill"
            case .ticket:    return "ticket.fill"
            case .budget:    return "tablecells.fill"
            case .flight:    return "airplane"
            case .event:     return "music.note.list"
            case .other:     return "doc.fill"
            }
        }

        /// Whether this type may have travel/event-specific fields
        var isTravelOrEvent: Bool {
            self == .flight || self == .event || self == .ticket
        }
    }

    // MARK: - Category

    enum Category: String, Codable, CaseIterable {
        case food           = "alimentación"
        case transport      = "transporte"
        case health         = "salud"
        case education      = "educación"
        case entertainment  = "entretenimiento"
        case home           = "hogar"
        case work           = "trabajo"
        case finance        = "finanzas"
        case shopping       = "compras"
        case utilities      = "suministros"
        case travel         = "viajes"
        case other          = "otro"

        var displayName: String {
            switch self {
            case .food:          return "Alimentación"
            case .transport:     return "Transporte"
            case .health:        return "Salud"
            case .education:     return "Educación"
            case .entertainment: return "Ocio"
            case .home:          return "Hogar"
            case .work:          return "Trabajo"
            case .finance:       return "Finanzas"
            case .shopping:      return "Compras"
            case .utilities:     return "Suministros"
            case .travel:        return "Viajes"
            case .other:         return "Otro"
            }
        }

        var emoji: String {
            switch self {
            case .food:          return "🛒"
            case .transport:     return "🚗"
            case .health:        return "💊"
            case .education:     return "📚"
            case .entertainment: return "🎬"
            case .home:          return "🏠"
            case .work:          return "💼"
            case .finance:       return "🏦"
            case .shopping:      return "🛍️"
            case .utilities:     return "💡"
            case .travel:        return "✈️"
            case .other:         return "📄"
            }
        }
    }

    // MARK: - Core fields (all document types)

    var documentType: DocumentType?
    /// Vendor, merchant, issuer, or airline name
    var vendor: String?
    /// ISO date string: YYYY-MM-DD
    var date: String?
    var amount: Double?
    /// ISO 4217 currency code: EUR, USD, GBP…
    var currency: String?
    var category: Category?

    // MARK: - Travel / event fields (flights, tickets, events)

    /// Origin city or airport code (e.g. "Madrid", "MAD")
    var origin: String?
    /// Destination city or airport code (e.g. "Barcelona", "BCN")
    var destination: String?
    /// Flight or train number (e.g. "IB6250", "AVE 02154")
    var flightNumber: String?
    /// Departure or event start time — HH:MM
    var departureTime: String?
    /// Arrival time — HH:MM
    var arrivalTime: String?
    /// Assigned seat or row (e.g. "23A", "Fila 12 Butaca 4")
    var seat: String?
    /// Concert, show, or event name
    var eventTitle: String?

    // MARK: - Computed helpers

    var formattedAmount: String? {
        guard let amount else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency ?? "EUR"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount))
    }

    var formattedDate: String? {
        guard let date else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        guard let parsed = iso.date(from: date) else { return date }
        return parsed.formatted(date: .abbreviated, time: .omitted)
    }

    var isEmpty: Bool {
        vendor == nil && date == nil && amount == nil && documentType == nil
    }
}
