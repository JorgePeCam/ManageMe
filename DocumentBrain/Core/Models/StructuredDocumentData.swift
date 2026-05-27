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
            case .other:     return "doc.fill"
            }
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

    // MARK: - Fields

    var documentType: DocumentType?
    /// Vendor, merchant, or issuer name
    var vendor: String?
    /// ISO date string: YYYY-MM-DD
    var date: String?
    var amount: Double?
    /// ISO 4217 currency code: EUR, USD, GBP…
    var currency: String?
    var category: Category?

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
