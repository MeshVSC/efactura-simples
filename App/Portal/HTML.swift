import Foundation

/// Small, targeted helpers for reading the e-Fatura pages.
enum HTML {
    static func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    static func unescape(_ s: String) -> String {
        var out = s
        let named = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'",
                     "&nbsp;": " ", "&euro;": "€"]
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v) }
        for m in matches(#"&#(\d+);"#, in: out).reversed() {
            if let code = UInt32(m[1]), let scalar = Unicode.Scalar(code) {
                out = out.replacingOccurrences(of: m[0], with: String(Character(scalar)))
            }
        }
        return out
    }

    /// Some portal text is UTF-8 that was decoded as Latin-1 on their side ("NÃ£o" for "Não").
    /// Re-encode those characters as Latin-1 bytes and read them back as UTF-8.
    static func repairMojibake(_ s: String) -> String {
        guard s.contains("Ã") || s.contains("Â"),
              let bytes = s.data(using: .isoLatin1),
              let fixed = String(data: bytes, encoding: .utf8) else { return s }
        return fixed
    }

    static func text(_ s: String) -> String {
        let noTags = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return repairMojibake(unescape(noTags))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// All matches; each entry holds the full match followed by its capture groups.
    static func matches(_ pattern: String, in s: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern,
                                                options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }

    static func first(_ pattern: String, in s: String, group: Int = 1) -> String? {
        matches(pattern, in: s).first.map { $0[group] }
    }

    static func attributes(of tag: String) -> [String: String] {
        var attrs: [String: String] = [:]
        for m in matches(#"([\w:-]+)\s*=\s*"([^"]*)""#, in: tag) {
            attrs[m[1].lowercased()] = unescape(m[2])
        }
        for m in matches(#"\s([\w-]+)(?=[\s>/])"#, in: tag) where attrs[m[1].lowercased()] == nil {
            attrs[m[1].lowercased()] = ""
        }
        return attrs
    }

    struct Form {
        var action: String
        var fields: [(name: String, value: String)]
    }

    /// The first form whose opening tag contains `marker` (an id or part of the action).
    static func form(containing marker: String, in html: String) -> Form? {
        for m in matches(#"(<form[^>]*>)(.*?)</form>"#, in: html) where m[1].contains(marker) {
            let attrs = attributes(of: m[1])
            var fields: [(String, String)] = []
            for input in matches(#"<input[^>]*>"#, in: m[2]) {
                let a = attributes(of: input[0])
                guard let name = a["name"], !name.isEmpty else { continue }
                let type = a["type"]?.lowercased() ?? "text"
                if (type == "checkbox" || type == "radio") && a["checked"] == nil { continue }
                fields.append((name, a["value"] ?? ""))
            }
            return Form(action: attrs["action"] ?? "", fields: fields)
        }
        return nil
    }

    /// Inner text of the element with this id, or its value attribute for inputs.
    static func value(ofId id: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: id)
        if let tag = first(#"(<input[^>]*id="\#(escaped)"[^>]*>)"#, in: html) {
            return attributes(of: tag)["value"]
        }
        if let inner = first(#"<(\w+)[^>]*id="\#(escaped)"[^>]*>(.*?)</\1>"#, in: html, group: 2) {
            return text(inner)
        }
        return nil
    }

    /// "2.695,84 €" -> 269584
    static func cents(_ s: String) -> Int {
        let cleaned = s.filter { $0.isNumber || $0 == "," || $0 == "-" }
        let parts = cleaned.split(separator: ",", omittingEmptySubsequences: false)
        let whole = Int(parts.first ?? "0") ?? 0
        var frac = parts.count > 1 ? String(parts[1].prefix(2)) : "0"
        if frac.count == 1 { frac += "0" }
        let f = Int(frac) ?? 0
        return whole < 0 || cleaned.hasPrefix("-") ? whole * 100 - f : whole * 100 + f
    }
}

extension Int {
    /// Cents formatted as euros, Portuguese style.
    var euros: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.locale = Locale(identifier: "pt_PT")
        return f.string(from: NSNumber(value: Double(self) / 100)) ?? "\(self)"
    }
}
