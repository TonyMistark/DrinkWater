import Foundation

struct PushError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 手机 / Apple Watch 推送。全部走各自服务商的 HTTPS 接口，
/// 不依赖 iCloud，也不需要额外的服务端。
enum RemotePush {

    static func send(settings: AppSettings,
                     title: String,
                     body: String,
                     completion: @escaping (Result<String, Error>) -> Void) {
        let prepared: (URLRequest, String)
        do {
            prepared = try makeRequest(settings: settings, title: title, body: body)
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        var request = prepared.0
        request.timeoutInterval = 12

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(error))
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(PushError(message: t("No response from server"))))
                    return
                }
                guard (200..<300).contains(http.statusCode) else {
                    let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    completion(.failure(PushError(message: t("HTTP {} {}", http.statusCode, String(text.prefix(120))))))
                    return
                }
                completion(.success(prepared.1))
            }
        }.resume()
    }

    // MARK: - 各服务商请求构造

    private static func makeRequest(settings: AppSettings,
                                    title: String,
                                    body: String) throws -> (URLRequest, String) {
        switch settings.pushProvider {
        case .none:
            throw PushError(message: t("No push method selected"))

        case .bark:
            let key = settings.barkKey.trimmed
            guard !key.isEmpty else { throw PushError(message: t("Please fill in the Bark device key")) }
            var base = settings.barkServer.trimmed
            if base.isEmpty { base = "https://api.day.app" }
            while base.hasSuffix("/") { base.removeLast() }
            guard let url = URL(string: base + "/push") else {
                throw PushError(message: t("Bark server URL is invalid"))
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = [
                "device_key": key,
                "title": title,
                "body": body,
                "group": "喝水提醒",
                "sound": "bell"
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            return (request, t("Push sent via Bark to iPhone"))

        case .ntfy:
            let topic = settings.ntfyTopic.trimmed
            guard !topic.isEmpty else { throw PushError(message: t("Please fill in the ntfy topic")) }
            var base = settings.ntfyServer.trimmed
            if base.isEmpty { base = "https://ntfy.sh" }
            while base.hasSuffix("/") { base.removeLast() }
            guard var comps = URLComponents(string: base + "/" + topic) else {
                throw PushError(message: t("ntfy URL is invalid"))
            }
            comps.queryItems = [
                URLQueryItem(name: "title", value: title),
                URLQueryItem(name: "tags", value: "droplet"),
                URLQueryItem(name: "priority", value: "default")
            ]
            guard let url = comps.url else { throw PushError(message: t("ntfy URL is invalid")) }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = body.data(using: .utf8)
            return (request, t("Push sent via ntfy"))

        case .pushover:
            let token = settings.pushoverToken.trimmed
            let user = settings.pushoverUser.trimmed
            guard !token.isEmpty, !user.isEmpty else {
                throw PushError(message: t("Please fill in the Pushover token and user key"))
            }
            guard let url = URL(string: "https://api.pushover.net/1/messages.json") else {
                throw PushError(message: t("Pushover URL is invalid"))
            }
            var comps = URLComponents()
            comps.queryItems = [
                URLQueryItem(name: "token", value: token),
                URLQueryItem(name: "user", value: user),
                URLQueryItem(name: "title", value: title),
                URLQueryItem(name: "message", value: body),
                URLQueryItem(name: "sound", value: "pushover")
            ]
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = comps.percentEncodedQuery?.data(using: .utf8)
            return (request, t("Push sent via Pushover"))

        case .custom:
            let template = settings.customURL.trimmed
            guard !template.isEmpty else { throw PushError(message: t("Please fill in a custom URL")) }
            let allowed = CharacterSet.urlQueryAllowed
            let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            let encodedBody = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            let filled = template
                .replacingOccurrences(of: "{title}", with: encodedTitle)
                .replacingOccurrences(of: "{body}", with: encodedBody)
            guard let url = URL(string: filled) else {
                throw PushError(message: t("Custom URL is invalid"))
            }
            var request = URLRequest(url: url)
            if settings.customMethod.uppercased() == "GET" {
                request.httpMethod = "GET"
            } else {
                request.httpMethod = "POST"
                request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["title": title, "body": body])
            }
            return (request, t("Custom webhook called"))
        }
    }
}
