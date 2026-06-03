import Configuration
import Hummingbird
import HummingbirdLambdaTesting
import Logging
import Testing

@testable import App

private let reader = ConfigReader(providers: [
    InMemoryProvider(values: [
        "log.level": "trace"
    ])
])

@Suite
struct AppTests {
    @Test
    func lambda() async throws {
        let lambda = try await buildLambda(reader: reader)
        try await lambda.test() { client in
            try await client.execute(uri: "/", method: .get) { response in
                #expect(response.body == "Hello!")
            }
        }
    }
}
