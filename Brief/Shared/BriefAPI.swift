import Foundation

enum Config {
    /// The rack hub - the same one Agents and Rack Control talk to, and the
    /// hub whose secret the shared Keychain token is. Resolves for anyone,
    /// routes only on the tailnet, so "unreachable" almost always means
    /// Tailscale is off.
    static let baseURL = URL(string: "https://example.com")!

    /// Shared by the app and the widget for the cached brief.
    static let appGroup = "group.com.example.brief"

    /// The widget's `kind`, so the app can ask WidgetKit to reload it.
    static let widgetKind = "BriefWidget"
}

/// What one `GET /api/brief` came back as.
enum BriefResult: Sendable {
    /// 200 with a brief, plus the exact bytes, which are what gets cached.
    case brief(Brief, Data)
    /// 404: the hub has not written today's first brief yet.
    case none
    /// 401: the token is wrong or was rotated.
    case unauthorized
    /// No answer at all - off the tailnet, or the hub is down.
    case unreachable
    /// Any other answer, or a 200 that would not decode.
    case failed(String)

    var message: String? {
        switch self {
        case .brief, .none: nil
        case .unauthorized: "That token was rejected."
        case .unreachable: "Can't reach the rack. Is Tailscale connected?"
        case .failed(let m): m
        }
    }
}

/// Why a chores call got no answer.
enum HubError: Error, Equatable, Sendable {
    case unauthorized
    case unreachable
    /// Any other answer: the status (0 = none) and words for the row.
    case failed(Int, String)

    var message: String {
        switch self {
        case .unauthorized: "That token was rejected."
        case .unreachable: "Can't reach the rack. Is Tailscale connected?"
        case .failed(_, let m): m
        }
    }

    /// mailgate's error codes, as the relay passes them on.
    static let words: [String: String] = [
        "bad_signature": "mailgate refused the signature. Is the approval key in Agents current?",
        "not_pending": "That Done expired. Tap it again.",
        "mailgate_unavailable": "mailgate isn't answering.",
        "not_configured": "mailgate isn't set up for this.",
        "timeout": "mailgate took too long. Pull to refresh before trying again.",
    ]
}

/// The one network call Brief makes for content. No state: the app and the
/// widget each hand it a token and decide for themselves what a result means.
enum BriefAPI {
    static func session(timeout: TimeInterval) -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = timeout
        c.timeoutIntervalForResource = timeout
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }

    static func request(_ path: String, token: String) -> URLRequest {
        var r = URLRequest(url: Config.baseURL.appending(path: path))
        r.setValue(token, forHTTPHeaderField: "x-rack-token")
        r.setValue("application/json", forHTTPHeaderField: "accept")
        return r
    }

    static func fetch(token: String, session: URLSession) async -> BriefResult {
        do {
            let (data, resp) = try await session.data(for: request("/api/brief", token: token))
            return classify(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        } catch let e as URLError {
            switch e.code {
            case .timedOut, .cannotFindHost, .cannotConnectToHost, .notConnectedToInternet,
                .networkConnectionLost, .dnsLookupFailed, .secureConnectionFailed:
                return .unreachable
            default:
                return .failed(e.localizedDescription)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Status + body -> result. Pure, so the tests can pin every branch.
    static func classify(status: Int, data: Data) -> BriefResult {
        switch status {
        case 200:
            do { return .brief(try Brief.decode(data), data) } catch {
                return .failed("Couldn't read the brief: \(error.localizedDescription)")
            }
        case 404: return .none
        case 401: return .unauthorized
        default:
            let body = String(data: data.prefix(200), encoding: .utf8) ?? ""
            return .failed("The hub answered \(status): \(body)")
        }
    }

    // MARK: chores

    /// `GET /api/chores`. A 404 is `.success(nil)`: a hub without the route yet
    /// just means no chores section.
    static func chores(token: String, session: URLSession) async -> Result<ChoresPage?, HubError> {
        switch await call(request("/api/chores", token: token), session: session, as: ChoresPage.self) {
        case .success(let page): .success(page)
        case .failure(.failed(404, _)): .success(nil)
        case .failure(let e): .failure(e)
        }
    }

    private struct Proposed: Decodable { let pending: ChorePending }
    private struct Finished: Decodable { let steps: ChoreSteps }

    /// `POST /api/chores/propose {id}` - only the row id; the hub proposes the
    /// row's own fields, and ChoreApproval checks what comes back.
    static func proposeChore(id: String, token: String, session: URLSession) async -> Result<ChorePending, HubError> {
        await call(post("/api/chores/propose", ["id": id], token: token), session: session, as: Proposed.self)
            .map(\.pending)
    }

    /// `POST /api/chores/done {id, approval, sig}` -> what each step did.
    static func finishChore(
        id: String, approval: String, sig: String, token: String, session: URLSession
    ) async -> Result<ChoreSteps, HubError> {
        let body = ["id": id, "approval": approval, "sig": sig]
        return await call(post("/api/chores/done", body, token: token), session: session, as: Finished.self)
            .map(\.steps)
    }

    static func post(_ path: String, _ body: [String: String], token: String) -> URLRequest {
        var r = request(path, token: token)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return r
    }

    private static func call<T: Decodable>(
        _ r: URLRequest, session: URLSession, as: T.Type
    ) async -> Result<T, HubError> {
        do {
            let (data, resp) = try await session.data(for: r)
            return classify(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data, as: T.self)
        } catch let e as URLError {
            switch e.code {
            case .timedOut, .cannotFindHost, .cannotConnectToHost, .notConnectedToInternet,
                .networkConnectionLost, .dnsLookupFailed, .secureConnectionFailed:
                return .failure(.unreachable)
            default:
                return .failure(.failed(0, e.localizedDescription))
            }
        } catch {
            return .failure(.failed(0, error.localizedDescription))
        }
    }

    /// Status + body -> result, for the chores calls. Pure, for the tests.
    static func classify<T: Decodable>(status: Int, data: Data, as: T.Type) -> Result<T, HubError> {
        switch status {
        case 200:
            do { return .success(try JSONDecoder().decode(T.self, from: data)) } catch {
                return .failure(.failed(200, "Couldn't read the hub's answer: \(error.localizedDescription)"))
            }
        case 401: return .failure(.unauthorized)
        default:
            // The mail relay's shape: {error, code}.
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if let code = body?["code"] as? String, let words = HubError.words[code] {
                return .failure(.failed(status, words))
            }
            let text = body?["error"] as? String ?? String(data: data.prefix(200), encoding: .utf8) ?? ""
            return .failure(.failed(status, "The hub answered \(status): \(text)"))
        }
    }

    /// Proves a pasted token before it is stored. EVERY /api/ route on the hub
    /// is behind the token gate, so a 401 is the only "no"; 200 and the
    /// 404 "no brief yet" both mean the token got through.
    static func validate(_ token: String) async -> Bool {
        var r = request("/api/brief", token: token)
        r.timeoutInterval = 15
        guard let (_, resp) = try? await URLSession.shared.data(for: r),
            let code = (resp as? HTTPURLResponse)?.statusCode
        else { return false }
        return code == 200 || code == 404
    }

    /// `POST /api/push/register`, the body agents-ios sends: hex token, APNs
    /// environment, and this app's own bundle id (the hub checks it against an
    /// allowlist and uses it as the apns-topic).
    static func registerForPush(token: String, deviceToken: String, environment: String) async -> Bool {
        var r = request("/api/push/register", token: token)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        let body = [
            "token": deviceToken,
            "env": environment,
            "bundle": Bundle.main.bundleIdentifier ?? "com.example.brief",
        ]
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (_, resp) = try? await URLSession.shared.data(for: r),
            let code = (resp as? HTTPURLResponse)?.statusCode
        else { return false }
        return (200..<300).contains(code)
    }
}

/// The last good brief, as the hub's own bytes, in the App Group container so
/// the widget can draw it. Falls back to Caches when the group container is
/// unavailable (an unsigned simulator build), which keeps the app working and
/// only costs the widget.
///
/// FILE PROTECTION: until first user authentication, to match the token's
/// AfterFirstUnlock - a widget refreshing on a locked phone must be able to
/// read it.
enum BriefCache {
    static var url: URL {
        let dir =
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Config.appGroup)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appending(path: "brief.json")
    }

    static func load() -> Brief? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Brief.decode(data)
    }

    /// When the cached copy was written - "updated 8:02".
    static func savedAt() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    static func save(_ data: Data) {
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func clear() { try? FileManager.default.removeItem(at: url) }
}
