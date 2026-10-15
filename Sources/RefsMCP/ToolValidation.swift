import Foundation
import CoreFoundation
import RefsCore

/// Checks the small JSON Schema subset used by the tool definitions before dispatch.
enum ToolValidation {
    static func validate(_ value: Any, schema: [String: Any], path: String = "arguments") throws {
        if let union = schema["anyOf"] as? [[String: Any]] {
            guard union.contains(where: { (try? validate(value, schema: $0, path: path)) != nil }) else {
                throw LibraryError.invalidInput("Invalid value for \(path).")
            }
            return
        }
        func invalid() -> LibraryError { .invalidInput("Invalid value for \(path).") }
        switch schema["type"] as? String {
        case "null": guard value is NSNull else { throw invalid() }
        case "string":
            guard let string = value as? String else { throw invalid() }
            if let choices = schema["enum"] as? [String], !choices.contains(string) {
                throw LibraryError.invalidInput("Invalid value for \(path). Expected one of: \(choices.joined(separator: ", ")).")
            }
            if let minimum = schema["minLength"] as? Int, string.count < minimum { throw invalid() }
        case "boolean":
            guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { throw invalid() }
        case "integer":
            guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
                  n.doubleValue.isFinite, n.doubleValue.rounded() == n.doubleValue,
                  n.doubleValue >= Double(Int.min), n.doubleValue < Double(Int.max) else { throw invalid() }
            if let min = schema["minimum"] as? Int, n.intValue < min { throw invalid() }
            if let max = schema["maximum"] as? Int, n.intValue > max { throw invalid() }
        case "array":
            guard let array = value as? [Any] else { throw invalid() }
            if let min = schema["minItems"] as? Int, array.count < min { throw invalid() }
            if let max = schema["maxItems"] as? Int, array.count > max { throw invalid() }
            for item in array { try validate(item, schema: schema["items"] as! [String: Any], path: path + "[]") }
        case "object":
            guard let object = value as? [String: Any] else { throw invalid() }
            let properties = schema["properties"] as? [String: Any] ?? [:]
            for key in schema["required"] as? [String] ?? [] where object[key] == nil {
                throw LibraryError.invalidInput("Missing \(path).\(key).")
            }
            for (key, item) in object {
                guard let property = properties[key] as? [String: Any] else {
                    throw LibraryError.invalidInput("Unknown field \(path).\(key).")
                }
                try validate(item, schema: property, path: path + "." + key)
            }
        default: throw invalid()
        }
    }
}
