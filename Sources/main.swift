import AppKit

// MARK: - Config

let pollInterval: TimeInterval = 60
let warnThreshold = 50.0   // >= orange
let critThreshold = 80.0   // >= red
// Weekly: 100% is split into 7 daily portions; the budget is the portions unlocked so far.
let weeklyWarnOfBudget = 0.85  // used >= 85% of today's budget -> orange
let weeklyCrit = 90.0          // used >= 90% of the whole week -> red
let fiveHours: TimeInterval = 5 * 3600
let sevenDays: TimeInterval = 7 * 24 * 3600

// MARK: - Model

struct Window {
    let utilization: Double
    let resetsAt: Date?
}

struct Usage {
    let fiveHour: Window?
    let sevenDay: Window?
    let fetchedAt: Date
}

enum FetchError: Error, CustomStringConvertible {
    case noCredentials
    case unauthorized
    case http(Int)
    case network(String)
    case decode

    var description: String {
        switch self {
        case .noCredentials: return "Credenziali Claude Code non trovate nel Portachiavi"
        case .unauthorized: return "Token scaduto: apri Claude Code per rinnovarlo"
        case .http(let code): return "Errore HTTP \(code)"
        case .network(let msg): return "Rete: \(msg)"
        case .decode: return "Risposta non valida"
        }
    }
}

// MARK: - Data source

/// Reads the OAuth token Claude Code stores in the login keychain.
/// Uses /usr/bin/security so the keychain ACL doesn't depend on this binary's signature.
func readAccessToken() -> String? {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    proc.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
    let out = Pipe()
    proc.standardOutput = out
    proc.standardError = Pipe()
    do { try proc.run() } catch { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    guard proc.terminationStatus == 0,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let oauth = json["claudeAiOauth"] as? [String: Any],
          let token = oauth["accessToken"] as? String
    else { return nil }
    return token
}

let isoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
let isoPlain = ISO8601DateFormatter()

func parseWindow(_ obj: Any?) -> Window? {
    guard let dict = obj as? [String: Any],
          let util = (dict["utilization"] as? NSNumber)?.doubleValue
    else { return nil }
    var reset: Date?
    if let s = dict["resets_at"] as? String {
        reset = isoFrac.date(from: s) ?? isoPlain.date(from: s)
    }
    return Window(utilization: util, resetsAt: reset)
}

func fetchUsage(completion: @escaping (Result<Usage, FetchError>) -> Void) {
    guard let token = readAccessToken() else { return completion(.failure(.noCredentials)) }
    var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    req.timeoutInterval = 20
    URLSession.shared.dataTask(with: req) { data, resp, err in
        if let err = err { return completion(.failure(.network(err.localizedDescription))) }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { return completion(.failure(.unauthorized)) }
        guard code == 200, let data = data else { return completion(.failure(.http(code))) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return completion(.failure(.decode))
        }
        completion(.success(Usage(fiveHour: parseWindow(json["five_hour"]),
                                  sevenDay: parseWindow(json["seven_day"]),
                                  fetchedAt: Date())))
    }.resume()
}

// MARK: - Formatting

func color(for pct: Double) -> NSColor {
    if pct >= critThreshold { return .systemRed }
    if pct >= warnThreshold { return .systemOrange }
    return .systemGreen
}

/// Current day of the weekly window (1...7) and the cumulative budget up to the end of it.
func weeklyBudget(resetsAt: Date?) -> (day: Int, budget: Double)? {
    guard let r = resetsAt else { return nil }
    let elapsed = sevenDays - r.timeIntervalSinceNow
    let day = min(7, max(1, Int(elapsed / 86400) + 1))
    return (day, Double(day) * 100 / 7)
}

func budgetLine(_ b: (day: Int, budget: Double)) -> String {
    "Budget settimanale fino a oggi: \(Int(b.budget.rounded()))% (giorno \(b.day)/7)"
}

func weeklyColor(_ w: Window) -> NSColor {
    if w.utilization >= weeklyCrit { return .systemRed }
    guard let b = weeklyBudget(resetsAt: w.resetsAt) else { return color(for: w.utilization) }
    return w.utilization >= b.budget * weeklyWarnOfBudget ? .systemOrange : .systemGreen
}

func countdown(to date: Date?) -> String {
    guard let date = date else { return "—" }
    let s = max(0, Int(date.timeIntervalSinceNow))
    let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
    if d > 0 { return "\(d)g \(h)h" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}

let resetFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "it_IT")
    f.dateFormat = "EEE d MMM HH:mm"
    return f
}()

/// Percentage of the window already elapsed, to compare against usage ("pace").
func elapsedPct(resetsAt: Date?, length: TimeInterval) -> Double? {
    guard let r = resetsAt else { return nil }
    let left = r.timeIntervalSinceNow
    return min(100, max(0, (1 - left / length) * 100))
}

func describe(_ name: String, _ w: Window?, length: TimeInterval) -> String {
    guard let w = w else { return "\(name): n/d" }
    var s = "\(name): \(Int(w.utilization.rounded()))% — reset tra \(countdown(to: w.resetsAt))"
    if let r = w.resetsAt { s += " (\(resetFormatter.string(from: r)))" }
    return s
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    var usage: Usage?
    var lastError: FetchError?
    var timer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        menu.delegate = self
        item.menu = menu
        setTitle(placeholder: "…")
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // Refresh right after wake from sleep.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self?.refresh() }
        }
    }

    @objc func refresh() {
        fetchUsage { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let u): self.usage = u; self.lastError = nil
                case .failure(let e): self.lastError = e
                }
                self.render()
            }
        }
    }

    func setTitle(placeholder: String) {
        item.button?.attributedTitle = NSAttributedString(string: placeholder, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        ])
    }

    func render() {
        guard let button = item.button else { return }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let labelFont = NSFont.systemFont(ofSize: 10, weight: .regular)
        let stale = lastError != nil

        guard let u = usage else {
            setTitle(placeholder: "Claude ⚠︎")
            button.toolTip = lastError?.description
            return
        }

        let title = NSMutableAttributedString()
        func add(_ label: String, _ w: Window?, _ colorOf: (Window) -> NSColor) {
            title.append(NSAttributedString(string: label, attributes: [
                .font: labelFont, .foregroundColor: NSColor.secondaryLabelColor,
                .baselineOffset: 1,
            ]))
            let pct = w?.utilization
            let text = pct.map { "\(Int($0.rounded()))%" } ?? "–"
            let col = stale ? NSColor.tertiaryLabelColor : (w.map(colorOf) ?? .secondaryLabelColor)
            title.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: col]))
        }
        add("5h ", u.fiveHour) { color(for: $0.utilization) }
        title.append(NSAttributedString(string: "  ", attributes: [.font: font]))
        add("7d ", u.sevenDay, weeklyColor)
        if stale {
            title.append(NSAttributedString(string: " ⚠︎", attributes: [.font: labelFont]))
        }
        button.attributedTitle = title

        var tip = [describe("Sessione 5h", u.fiveHour, length: fiveHours),
                   describe("Settimana", u.sevenDay, length: sevenDays)]
        if let b = weeklyBudget(resetsAt: u.sevenDay?.resetsAt) {
            tip.append(budgetLine(b))
        }
        if let e = lastError { tip.append("⚠︎ \(e.description)") }
        button.toolTip = tip.joined(separator: "\n")
    }

    // Rebuild the menu each time it opens so countdowns are fresh.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func info(_ s: String) {
            let i = NSMenuItem(title: s, action: nil, keyEquivalent: "")
            i.isEnabled = false
            menu.addItem(i)
        }
        if let u = usage {
            info(describe("Sessione 5h", u.fiveHour, length: fiveHours))
            if let e = elapsedPct(resetsAt: u.fiveHour?.resetsAt, length: fiveHours) {
                info("    tempo trascorso: \(Int(e))%")
            }
            info(describe("Settimana", u.sevenDay, length: sevenDays))
            if let b = weeklyBudget(resetsAt: u.sevenDay?.resetsAt) {
                info("    " + budgetLine(b))
            }
            menu.addItem(.separator())
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
            info("Aggiornato alle \(f.string(from: u.fetchedAt))")
        }
        if let e = lastError { info("⚠︎ \(e.description)") }
        menu.addItem(.separator())
        let r = NSMenuItem(title: "Aggiorna ora", action: #selector(refresh), keyEquivalent: "r")
        r.target = self
        menu.addItem(r)
        menu.addItem(NSMenuItem(title: "Esci", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
