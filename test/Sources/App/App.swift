import Configuration
import Hummingbird
import Logging

@main
struct Lambda {
    static func main() async throws {
        let reader = ConfigReader(providers: [
            EnvironmentVariablesProvider()
        ])
        let lambda = try await buildLambda(reader: reader)
        try await lambda.runService()
    }
}
