import Foundation

@MainActor
public final class ExportCSVUseCase {
    private let measurementsRepository: any MeasurementsRepository

    public init(measurementsRepository: any MeasurementsRepository) {
        self.measurementsRepository = measurementsRepository
    }

    /// Exports measurements to a CSV file in the temporary directory and returns its URL.
    /// - Parameters:
    ///   - startDate: Inclusive start date.
    ///   - endDate: Inclusive end date.
    ///   - includeBP: Whether to include blood pressure measurements.
    ///   - includeGlucose: Whether to include glucose measurements.
    public func exportCSV(from startDate: Date, to endDate: Date, includeBP: Bool, includeGlucose: Bool) async throws -> URL {
        // Fetch models on the main actor via the repository.
        let bpDTOs: [BPRowDTO]
        if includeBP {
            let bp = try await measurementsRepository.bpMeasurements(from: startDate, to: endDate)
            bpDTOs = bp.map { BPRowDTO(model: $0) }
        } else {
            bpDTOs = []
        }

        let glucoseDTOs: [GlucoseRowDTO]
        if includeGlucose {
            let glucose = try await measurementsRepository.glucoseMeasurements(from: startDate, to: endDate)
            glucoseDTOs = glucose.map { GlucoseRowDTO(model: $0) }
        } else {
            glucoseDTOs = []
        }

        // Build CSV content off the main actor using only DTOs
        let (csvData, fileName): (Data, String) = try await Task.detached(priority: .utility) { @Sendable () throws -> (Data, String) in
            var sections: [CSVSection] = []
            if includeBP {
                sections.append(CSVBuilder.makeBPSection(rows: bpDTOs))
            }
            if includeGlucose {
                sections.append(CSVBuilder.makeGlucoseSection(rows: glucoseDTOs))
            }
            let combined = CSVBuilder.combine(sections: sections)
            guard let data = combined.data(using: .utf8) else {
                throw ExportCSVError.encodingFailed
            }
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withFullDate]
            let startStr = dateFormatter.string(from: startDate)
            let endStr = dateFormatter.string(from: endDate)
            let name: String
            switch (includeBP, includeGlucose) {
            case (true, true): name = "DDiary_Export_BP_Glucose_\(startStr)_to_\(endStr).csv"
            case (true, false): name = "DDiary_Export_BP_\(startStr)_to_\(endStr).csv"
            case (false, true): name = "DDiary_Export_Glucose_\(startStr)_to_\(endStr).csv"
            default: name = "DDiary_Export_\(startStr)_to_\(endStr).csv"
            }
            return (data, name)
        }.value

        // Write to a temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try csvData.write(to: tempURL, options: [.atomic])
        return tempURL
    }
}

// MARK: - DTOs (Sendable)

private struct BPRowDTO: Sendable {
    let id: UUID
    let timestamp: Date
    let systolic: Int
    let diastolic: Int
    let pulse: Int
    let comment: String?

    init(model: BPMeasurement) {
        self.id = model.id
        self.timestamp = model.timestamp
        self.systolic = model.systolic
        self.diastolic = model.diastolic
        self.pulse = model.pulse
        self.comment = model.comment
    }
}

private struct GlucoseRowDTO: Sendable {
    let id: UUID
    let timestamp: Date
    let value: Double
    let unit: String
    let measurementType: String
    let mealSlot: String
    let comment: String?

    init(model: GlucoseMeasurement) {
        self.id = model.id
        self.timestamp = model.timestamp
        self.value = model.value
        self.unit = model.unit.rawValue
        self.measurementType = model.measurementType.rawValue
        self.mealSlot = model.mealSlot.rawValue
        self.comment = model.comment
    }
}

// MARK: - CSV Builder

private enum ExportCSVError: Error {
    case encodingFailed
}

private struct CSVSection {
    let title: String
    let header: [String]
    let rows: [[String]]
}

private enum CSVBuilder {
    nonisolated static func makeBPSection(rows: [BPRowDTO]) -> CSVSection {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.calendar = Calendar(identifier: .gregorian)
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"

        let header = [
            "timestamp",
            "date",
            "time",
            "systolic",
            "diastolic",
            "pulse",
            "comment",
            "id"
        ]
        let r = rows.sorted { $0.timestamp < $1.timestamp }.map { row in
            [
                isoFormatter.string(from: row.timestamp),
                dateFormatter.string(from: row.timestamp),
                timeFormatter.string(from: row.timestamp),
                String(row.systolic),
                String(row.diastolic),
                String(row.pulse),
                sanitize(row.comment),
                row.id.uuidString
            ]
        }
        return CSVSection(title: "BP", header: header, rows: r)
    }

    nonisolated static func makeGlucoseSection(rows: [GlucoseRowDTO]) -> CSVSection {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.calendar = Calendar(identifier: .gregorian)
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"

        let header = [
            "timestamp",
            "date",
            "time",
            "value",
            "unit",
            "measurementType",
            "mealSlot",
            "comment",
            "id"
        ]
        let r = rows.sorted { $0.timestamp < $1.timestamp }.map { row in
            [
                isoFormatter.string(from: row.timestamp),
                dateFormatter.string(from: row.timestamp),
                timeFormatter.string(from: row.timestamp),
                String(format: "%.3f", row.value),
                row.unit,
                row.measurementType,
                row.mealSlot,
                sanitize(row.comment),
                row.id.uuidString
            ]
        }
        return CSVSection(title: "Glucose", header: header, rows: r)
    }

    nonisolated static func combine(sections: [CSVSection]) -> String {
        var out = ""
        for (index, section) in sections.enumerated() {
            if !section.title.isEmpty {
                out += "# \(section.title)\n"
            }
            out += csvLine(from: section.header) + "\n"
            for row in section.rows {
                out += csvLine(from: row) + "\n"
            }
            if index < sections.count - 1 {
                out += "\n"
            }
        }
        return out
    }

    nonisolated private static func csvLine(from fields: [String]) -> String {
        fields.map { csvEscape($0) }.joined(separator: ",")
    }

    nonisolated private static func csvEscape(_ field: String) -> String {
        var needsQuotes = false
        var out = ""
        for ch in field {
            if ch == "\"" {
                out.append("\"")
                out.append("\"")
                needsQuotes = true
            } else {
                if ch == "," || ch == "\n" || ch == "\r" { needsQuotes = true }
                out.append(ch)
            }
        }
        return needsQuotes ? "\"\(out)\"" : out
    }

    nonisolated private static func sanitize(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        return value
    }
}

