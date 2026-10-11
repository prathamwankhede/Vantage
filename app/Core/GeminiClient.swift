import Foundation

enum GeminiClient {
    enum Failure: Error {
        /// No network path (airplane mode, no Wi-Fi or cell).
        case offline
        /// Reached Google but no reply in time — the model is slow right now.
        case timedOut
        case quota(retryAfter: TimeInterval)
        case failed
    }

    struct NavigateStep: Decodable {
        let landmark: String
        let action: String
        let bearing: String
        let confidence: String
        let arrived: Bool
        let unsure: Bool
        /// Landmark box in the upright photo: [ymin, xmin, ymax, xmax], each 0–1000 (Gemini's box format).
        var box2D: [Double]? = nil
        /// The landmark is the destination itself, not a waypoint on the way.
        var isGoal: Bool? = nil

        enum CodingKeys: String, CodingKey {
            case landmark, action, bearing, confidence, arrived, unsure
            case box2D = "box_2d"
            case isGoal = "is_goal"
        }

        /// Centre of the landmark box, normalized 0–1 with a top-left origin.
        var uprightCenter: SIMD2<Float>? {
            guard let box = box2D, box.count == 4 else { return nil }
            let (ymin, xmin, ymax, xmax) = (box[0], box[1], box[2], box[3])
            guard ymax > ymin, xmax > xmin else { return nil }
            let center = SIMD2(Float((xmin + xmax) / 2000), Float((ymin + ymax) / 2000))
            guard (0...1).contains(center.x), (0...1).contains(center.y) else { return nil }
            return center
        }

        var spoken: String {
            if unsure || confidence.lowercased() == "low" {
                return "I'm not sure. \(action)"
            }
            return action
        }

        var zoneHint: Zone? {
            switch bearing.lowercased() {
            case "left": return .left
            case "right": return .right
            case "ahead", "center", "forward": return .center
            default: return nil
            }
        }
    }

    /// How every prompt introduces the phone's own measurements.
    static func sensorBlock(_ sensors: String) -> String {
        """
        Phone sensor readings taken with this photo. They are measured, so trust them over \
        your own visual estimate for distances, motion and what is closest; use the photo for \
        what things are. If anything is within 2 m (6 ft), mention it first. Give distances in \
        feet only, never metres. Don't promise the way is safe — report what the sensors measured.
        \(sensors)
        """
    }

    static func answer(_ question: String, in jpeg: Data, sensors: String) async throws -> String {
        let prompt = """
        You are Vantage, a calm guide for a blind or low-vision person. \
        This photo is from a phone on their chest. Answer in under 25 words. \
        Use left, ahead, or right. Be honest if unsure — say you think or aren't sure. \
        Never claim you can detect glass. Do not invent street names or signal colors. \
        This is situational awareness, not turn-by-turn GPS routing.

        \(sensorBlock(sensors))

        Question: \(question)
        """
        return try await generate(prompt: prompt, jpeg: jpeg, json: false)
    }

    static func navigateStep(goal: String, lastStep: String, in jpeg: Data, sensors: String) async throws -> NavigateStep {
        let prompt = """
        You are Vantage, guiding a blind or low-vision person to a destination using only what is \
        visible in this chest-worn camera photo. There is no map and no GPS. \
        Destination: \(goal). \
        Previous step you gave: \(lastStep.isEmpty ? "(none)" : lastStep). \
        Pick ONE visible landmark to walk to next — the destination itself if you can see it, otherwise \
        something on the way such as a door, a hallway opening, a counter, or a sign. Prefer things at walking \
        level on the floor ahead. \
        Reply ONLY with JSON matching this schema: \
        {"landmark":"short name of that landmark, or empty","action":"one short imperative under 16 words",\
        "bearing":"left|ahead|right","confidence":"high|medium|low","arrived":false,"unsure":false,\
        "box_2d":[ymin,xmin,ymax,xmax],"is_goal":false}. \
        box_2d is a tight box around that landmark in this photo, each value 0-1000; use [] if there is no \
        useful landmark. is_goal is true only if the landmark is the destination itself. \
        If the destination appears reached, set arrived true. If you cannot see useful clues, set unsure true \
        and say so in action. Never invent room numbers or street names that are not readable in the photo. \
        Don't send them toward a side the sensors say is blocked within 1 metre.

        \(sensorBlock(sensors))
        """
        let raw = try await generate(prompt: prompt, jpeg: jpeg, json: true)
        return try decodeStep(raw)
    }

    private static func decodeStep(_ raw: String) throws -> NavigateStep {
        let trimmed = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { throw Failure.failed }
        do {
            return try JSONDecoder().decode(NavigateStep.self, from: data)
        } catch {
            // Model sometimes wraps fields loosely — give a safe spoken fallback.
            return NavigateStep(
                landmark: "",
                action: trimmed.count < 120 ? trimmed : "I'm not sure. Look around slowly and ask again.",
                bearing: "ahead",
                confidence: "low",
                arrived: false,
                unsure: true
            )
        }
    }

    private static func generate(prompt: String, jpeg: Data, json: Bool) async throws -> String {
        var request: URLRequest
        if Secrets.backendURL.isEmpty {
            guard !Secrets.geminiKey.isEmpty,
                  let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(Secrets.geminiModel):generateContent")
            else { throw Failure.failed }
            request = URLRequest(url: url)
            request.setValue(Secrets.geminiKey, forHTTPHeaderField: "x-goog-api-key")
        } else {
            guard let url = URL(string: Secrets.backendURL + "/gemini") else { throw Failure.failed }
            request = URLRequest(url: url)
            request.setValue(Secrets.backendKey, forHTTPHeaderField: "x-functions-key")
        }

        var generationConfig: [String: Any] = ["temperature": 0.2]
        if json { generationConfig["responseMimeType"] = "application/json" }
        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["inline_data": ["mime_type": "image/jpeg", "data": jpeg.base64EncodedString()]],
                    ["text": prompt]
                ]
            ]],
            "generationConfig": generationConfig
        ]
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20

        var (data, status) = try await send(request)
        // Gemini sometimes answers a valid request with an empty 404 or a 5xx; one retry clears it.
        if status == 404 || status >= 500 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            (data, status) = try await send(request)
        }
        if status == 429 { throw Failure.quota(retryAfter: retryDelay(in: data) ?? 60) }
        guard status == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else { throw Failure.failed }
        return parts.compactMap { $0["text"] as? String }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw Failure.timedOut
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
                 .internationalRoamingOff, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                throw Failure.offline
            default:
                throw Failure.failed
            }
        } catch {
            throw Failure.failed
        }
    }

    private static func retryDelay(in data: Data) -> TimeInterval? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let details = (root["error"] as? [String: Any])?["details"] as? [[String: Any]]
        else { return nil }
        for detail in details {
            if let delay = detail["retryDelay"] as? String,
               let seconds = TimeInterval(delay.dropLast()) {
                return seconds
            }
        }
        return nil
    }
}
