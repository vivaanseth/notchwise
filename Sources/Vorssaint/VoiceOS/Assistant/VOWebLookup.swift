import Foundation

/// Finds the page a lookup means, a person's profile, so the assistant opens
/// the profile itself rather than a list to pick from. It reads a search
/// engine's plain results page; only the words of the request leave the Mac,
/// as they would typed into the search engine. Bing, because DuckDuckGo's
/// plain page turns automated requests away.
enum VOWebLookup {
    struct Hit: Equatable {
        let url: URL
        let title: String
    }

    /// A site whose profiles a lookup can land on.
    struct Site {
        let name: String
        /// How it is said, as a regular expression.
        let spoken: String
        /// The site's own search for a name: where a lookup lands without a profile.
        let search: (String) -> URL
        let isProfile: (URL) -> Bool
    }

    static let sites: [Site] = [
        Site(name: "LinkedIn", spoken: #"linked\s*in"#,
             search: { url("https://www.linkedin.com/search/results/people/", "keywords", $0) },
             isProfile: { on($0, "linkedin.com") && $0.pathComponents.count >= 3 && $0.pathComponents[1] == "in" }),
        Site(name: "GitHub", spoken: #"git\s*hub"#,
             search: { url("https://github.com/search", "q", $0, ["type": "users"]) },
             isProfile: { on($0, "github.com") && $0.pathComponents.count == 2 }),
        Site(name: "Instagram", spoken: #"insta(?:gram)?"#,
             search: { url("https://www.instagram.com/explore/search/keyword/", "q", $0) },
             isProfile: { on($0, "instagram.com") && $0.pathComponents.count == 2
                 && !["explore", "p", "reel", "reels", "stories"].contains($0.pathComponents[1]) }),
        Site(name: "X", spoken: #"twitter|x\.com|on\s+x"#,
             search: { url("https://x.com/search", "q", $0, ["f": "user"]) },
             isProfile: { (on($0, "x.com") || on($0, "twitter.com")) && $0.pathComponents.count == 2
                 && !["search", "home", "explore", "i", "hashtag"].contains($0.pathComponents[1]) }),
    ]

    /// The site a request names, if any.
    static func site(in text: String) -> Site? {
        sites.first { text.range(of: #"(?i)\b(?:"# + $0.spoken + #")\b"#, options: .regularExpression) != nil }
    }

    /// Profiles on `site` among `hits` whose title or address carries every
    /// word of `name`, in the search engine's order, each once.
    static func profiles(_ hits: [Hit], on site: Site, named name: String) -> [Hit] {
        let words = fold(name).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 2 }
        guard !words.isEmpty else { return [] }
        var seen = Set<String>()
        return hits.filter { hit in
            guard site.isProfile(hit.url) else { return false }
            let haystack = fold(hit.title + " " + hit.url.path)
            guard words.allSatisfy(haystack.contains) else { return false }
            // in.linkedin.com and www.linkedin.com show the same profile.
            return seen.insert(hit.url.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))).inserted
        }
    }

    /// The search engine's results for `query`, or none when it cannot be
    /// reached in `timeout` seconds.
    static func search(_ query: String, timeout: TimeInterval = 5) async -> [Hit] {
        var request = URLRequest(url: url("https://www.bing.com/search", "q", query, ["setlang": "en"]), timeoutInterval: timeout)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else { return [] }
        return parseBing(html)
    }

    /// Each result's heading link. Bing puts the address behind a click
    /// redirect whose `u` parameter is "a1" and the address in URL-safe base64.
    static func parseBing(_ html: String) -> [Hit] {
        guard let regex = try? NSRegularExpression(pattern: #"<h2[^>]*>\s*<a[^>]*?href="([^"]+)"[^>]*>(.*?)</a>"#,
                                                   options: [.dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let hrefRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else { return nil }
            let href = unescape(String(html[hrefRange]))
            let title = unescape(String(html[titleRange]).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let target = destination(of: href), !title.isEmpty else { return nil }
            return Hit(url: target, title: title)
        }
    }

    private static func destination(of href: String) -> URL? {
        guard let link = URLComponents(string: href) else { return nil }
        if link.host?.hasSuffix("bing.com") == true {
            guard let encoded = link.queryItems?.first(where: { $0.name == "u" })?.value, encoded.hasPrefix("a1") else { return nil }
            var base64 = String(encoded.dropFirst(2)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
            guard let data = Data(base64Encoded: base64), let address = String(data: data, encoding: .utf8) else { return nil }
            return URL(string: address)
        }
        return link.scheme?.hasPrefix("http") == true ? link.url : nil
    }

    /// Named entities a results page uses, and numbered ones such as "&#183;".
    private static func unescape(_ text: String) -> String {
        var out = text
        for (entity, character) in [("&quot;", "\""), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            out = out.replacingOccurrences(of: entity, with: character)
        }
        if let numbered = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            for match in numbered.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed() {
                guard let whole = Range(match.range, in: out), let digits = Range(match.range(at: 2), in: out),
                      let hex = Range(match.range(at: 1), in: out),
                      let code = UInt32(out[digits], radix: out[hex].isEmpty ? 10 : 16),
                      let scalar = Unicode.Scalar(code) else { continue }
                out.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func on(_ url: URL, _ domain: String) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == domain || host.hasSuffix("." + domain)
    }

    private static func url(_ base: String, _ key: String, _ value: String, _ extra: [String: String] = [:]) -> URL {
        var components = URLComponents(string: base)!
        components.queryItems = [URLQueryItem(name: key, value: value)]
            + extra.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }
}
