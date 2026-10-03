import Foundation

/// One entry in the site's "Grupy" tree (the left frame of plany.ubb.edu.pl):
/// department → study mode → course → degree → semester → group → subgroup.
/// Inner nodes from the semester down are plans themselves too (`plan.php?type=2`).
struct PlanTreeNode: Hashable, Identifiable {
    /// The id to expand this node with, or nil for a leaf.
    var branchID: Int?
    var name: String
    /// The plan this node opens, if it links to one.
    var plan: PlanSource?

    var id: String { branchID.map { "b\($0)" } ?? plan.map { "p\($0.type)-\($0.id)" } ?? name }
    var isLeaf: Bool { branchID == nil }
}

enum PlanTreeParser {
    /// Departments from `left_menu.php`: `branch(1,6153,0,'Wydział …')`.
    static func roots(in html: String) -> [PlanTreeNode] {
        matches("branch\\(1,\\s*(\\d+),\\s*\\d+,\\s*'([^']*)'\\)", in: html).compactMap { m in
            Int(m[1]).map { PlanTreeNode(branchID: $0, name: PlanHTMLParser.decode(m[2]).trimmed) }
        }
    }

    /// One level from `left_menu_feed.php`: a flat `<ul>` of `<li>` items. Each item is
    /// either expandable (`get_left_tree_branch( 'id', … )`) or a leaf, and its name is
    /// either plain text or a link to a plan.
    static func children(in html: String) -> [PlanTreeNode] {
        html.components(separatedBy: "<li").dropFirst().compactMap { item in
            let branch = matches("get_left_tree_branch\\(\\s*'(\\d+)'", in: item).first.flatMap { Int($0[1]) }
            if let link = matches("href=\"plan\\.php\\?type=(\\d+)&(?:amp;)?id=(\\d+)\"[^>]*>([^<]+)</a>", in: item).first,
               let type = Int(link[1]), let id = Int(link[2]) {
                return PlanTreeNode(branchID: branch, name: PlanHTMLParser.decode(link[3]).trimmed, plan: PlanSource(type: type, id: id))
            }
            guard let branch, let text = matches(">\\s*([^<>]+?)\\s*<div", in: item).first else { return nil }
            return PlanTreeNode(branchID: branch, name: PlanHTMLParser.decode(text[1]).trimmed)
        }
    }

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { i in
                Range(match.range(at: i), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }
}

/// Fetches levels of the group tree, one request per level, as the site's left frame does.
struct PlanTreeService {
    private static let base = URL(string: "https://plany.ubb.edu.pl/")!
    var session: URLSession = .shared

    /// The departments (`parent == nil`) or the children of `parent`.
    func children(of parent: PlanTreeNode?) async throws -> [PlanTreeNode] {
        guard let parent else {
            return PlanTreeParser.roots(in: try await get("left_menu.php", query: [:]))
        }
        guard let branch = parent.branchID else { return [] }
        let html = try await get("left_menu_feed.php", query: ["type": "1", "branch": "\(branch)", "link": "0", "bOne": "1"])
        return PlanTreeParser.children(in: html)
    }

    private func get(_ path: String, query: [String: String]) async throws -> String {
        var comps = URLComponents(url: Self.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        let (data, response) = try await session.data(for: URLRequest(url: comps.url!, timeoutInterval: 20))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ScheduleError.badResponse(http.statusCode)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

extension PlanTreeNode {
    /// A short title for a list of siblings: drops the path they share and spells out the
    /// common patterns ("Inf/NZ/Ist/3sem" → "Semester 3", "…/1gr" → "Group 1", "…/1gr/b" → "Subgroup b").
    func shortName(among siblings: [PlanTreeNode]) -> String {
        let shared = siblings.count > 1 ? Self.sharedPathPrefix(siblings.map(\.name)) : Self.parentPath(name)
        let last = (shared.isEmpty ? name : String(name.dropFirst(shared.count))).trimmed
        if let n = last.wholeMatch(of: #/(\d+)\s*sem/#)?.1 { return String(localized: "Semester \(String(n))") }
        if let n = last.wholeMatch(of: #/(\d+)\s*gr/#)?.1 { return String(localized: "Group \(String(n))") }
        if isLeaf, plan != nil, last.count <= 2, last != name { return String(localized: "Subgroup \(last)") }
        return last.isEmpty ? name : last
    }

    /// The longest common prefix that ends with "/" (so whole path segments only).
    private static func sharedPathPrefix(_ names: [String]) -> String {
        guard var prefix = names.first else { return "" }
        for name in names.dropFirst() {
            while !name.hasPrefix(prefix) { prefix.removeLast() }
        }
        guard let slash = prefix.lastIndex(of: "/") else { return "" }
        return String(prefix[...slash])
    }

    private static func parentPath(_ name: String) -> String {
        guard let slash = name.lastIndex(of: "/"), name.index(after: slash) < name.endIndex else { return "" }
        return String(name[...slash])
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
