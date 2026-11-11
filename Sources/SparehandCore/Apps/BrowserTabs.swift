import Foundation

/// Reads open tab titles and URLs from running browsers. Records are "title␟url␞".
public enum BrowserTabs {
    public static let chromeFamily = ["Google Chrome", "Arc", "Dia", "Brave Browser", "Microsoft Edge"]

    public static func listScript(app: String) -> String {
        """
        tell application \(AppleScriptText.quoted(app))
          set out to ""
          repeat with w in windows
            repeat with t in tabs of w
              set out to out & (title of t) & (ASCII character 31) & (URL of t) & (ASCII character 30)
            end repeat
          end repeat
          return out
        end tell
        """
    }

    public static func safariListScript() -> String {
        """
        tell application "Safari"
          set out to ""
          repeat with w in windows
            repeat with t in tabs of w
              set out to out & (name of t) & (ASCII character 31) & (URL of t) & (ASCII character 30)
            end repeat
          end repeat
          return out
        end tell
        """
    }

    /// Only http(s) tabs with a title.
    public static func parse(_ output: String, browser: String) -> [Tab] {
        output.split(separator: "\u{1E}").compactMap { record in
            let parts = record.split(separator: "\u{1F}", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, let url = URL(string: String(parts[1])), ["http", "https"].contains(url.scheme ?? "") else { return nil }
            return Tab(browser: browser, title: title, url: url)
        }
    }

    /// Tabs from every running browser. A browser that refuses (no Automation permission) contributes nothing.
    public static func all(runner: ScriptRunner, running: Set<String>) async -> [Tab] {
        var tabs: [Tab] = []
        for app in chromeFamily + ["Safari"] where running.contains(app) {
            let script = app == "Safari" ? safariListScript() : listScript(app: app)
            guard let out = try? await runner.run(script) else { continue }
            tabs += parse(out, browser: app)
        }
        return tabs
    }
}
