import XCTest
@testable import MagicTextCore

/// Mock URLProtocol so GatewayClient is tested without any network.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class GatewayClientTests: XCTestCase {
    private func mockedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func client(model: String = "m1") -> GatewayClient {
        GatewayClient(
            config: GatewayConfig(baseURL: "https://gw.test/v1", model: model),
            keychain: FakeKeychain(),
            session: mockedSession()
        )
    }

    private func keyFromRequest() -> String? {
        MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization")
    }

    // MARK: listModels

    func testListModelsOpenAIShape() async throws {
        MockURLProtocol.handler = { _ in
            (200, #"{"data":[{"id":"gpt-4o"},{"id":"gpt-4o-mini"}]}"#.data(using: .utf8)!)
        }
        let models = try await client().listModels()
        XCTAssertEqual(models, ["gpt-4o", "gpt-4o-mini"])
    }

    func testListModelsBareArrayShape() async throws {
        MockURLProtocol.handler = { _ in
            (200, #"["llama3","qwen2"]"#.data(using: .utf8)!)
        }
        let models = try await client().listModels()
        XCTAssertEqual(models, ["llama3", "qwen2"])
    }

    func testListModels401() async {
        MockURLProtocol.handler = { _ in (401, Data("nope".utf8)) }
        do {
            _ = try await client().listModels()
            XCTFail("expected throw")
        } catch let e as GatewayError {
            XCTAssertEqual(e, .unauthorized)
        } catch { XCTFail("wrong error: \(error)") }
    }

    func testListModelsEmpty() async {
        MockURLProtocol.handler = { _ in (200, #"{"data":[]}"#.data(using: .utf8)!) }
        do {
            _ = try await client().listModels()
            XCTFail("expected throw")
        } catch let e as GatewayError {
            XCTAssertEqual(e, .emptyResponse)
        } catch { XCTFail("wrong error: \(error)") }
    }

    // MARK: refine

    func testRefineHappyPath() async throws {
        MockURLProtocol.handler = { _ in
            (200, #"{"choices":[{"message":{"content":"  Fixed text.  "}}]}"#.data(using: .utf8)!)
        }
        let out = try await client().refine("fixxed text")
        XCTAssertEqual(out, "Fixed text.")
    }

    func testRefineStripsCodeFence() async throws {
        MockURLProtocol.handler = { _ in
            (200, #"{"choices":[{"message":{"content":"```\nfixed\n```"}}]}"#.data(using: .utf8)!)
        }
        let out = try await client().refine("fixxed")
        XCTAssertEqual(out, "fixed")
    }

    func testRefine500() async {
        MockURLProtocol.handler = { _ in (500, Data("boom".utf8)) }
        do {
            _ = try await client().refine("x")
            XCTFail("expected throw")
        } catch let e as GatewayError {
            if case .server(let code, _) = e { XCTAssertEqual(code, 500) } else { XCTFail("wrong: \(e)") }
        } catch { XCTFail("wrong error: \(error)") }
    }

    func testRefineEmptyChoices() async {
        MockURLProtocol.handler = { _ in
            (200, #"{"choices":[]}"#.data(using: .utf8)!)
        }
        do {
            _ = try await client().refine("x")
            XCTFail("expected throw")
        } catch let e as GatewayError {
            XCTAssertEqual(e, .emptyResponse)
        } catch { XCTFail("wrong error: \(error)") }
    }

    func testRefineRequestShape() async throws {
        MockURLProtocol.handler = { _ in
            (200, #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!)
        }
        _ = try await client(model: "test-model").refine("hello world")
        let req = MockURLProtocol.lastRequest
        XCTAssertEqual(req?.url?.absoluteString, "https://gw.test/v1/chat/completions")
        XCTAssertEqual(req?.httpMethod, "POST")
        let body = try XCTUnwrap(req?.httpBody ?? req?.httpBodyStream.map { stream -> Data in
            stream.open(); defer { stream.close() }
            var data = Data(); let bufSize = 4096
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
            defer { buf.deallocate() }
            while stream.hasBytesAvailable {
                let n = stream.read(buf, maxLength: bufSize)
                if n <= 0 { break }
                data.append(buf, count: n)
            }
            return data
        })
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "test-model")
        XCTAssertEqual(json["temperature"] as? Double, 0)
        XCTAssertNotNil(json["max_tokens"] as? Int)
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[1]["content"] as? String, "hello world")
    }

    func testRefineUsesKeychainKey() async throws {
        MockURLProtocol.handler = { _ in
            (200, #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!)
        }
        let keychain = FakeKeychain()
        keychain.save("sk-test-123", for: KeychainAccount.gatewayKey)
        let c = GatewayClient(config: GatewayConfig(baseURL: "https://gw.test/v1", model: "m"),
                              keychain: keychain, session: mockedSession())
        _ = try await c.refine("x")
        XCTAssertEqual(keyFromRequest(), "Bearer sk-test-123")
    }
}
