import AWSLambdaEvents
import Configuration
import Hummingbird
import HummingbirdLambda
import Logging

// Request context used by lambda<APIGatewayRequest>
typealias AppRequestContext = BasicLambdaRequestContext<APIGatewayRequest>

///  Build AWS Lambda function
/// - Parameter reader: configuration reader
func buildLambda(reader: ConfigReader) async throws -> APIGatewayLambdaFunction<RouterResponder<AppRequestContext>> {
    let logger = {
        var logger = Logger(label: "test")
        logger.logLevel = reader.string(forKey: "log.level", as: Logger.Level.self, default: .info)
        return logger
    }()
    let router = try buildRouter()
    let lambda = APIGatewayLambdaFunction(
        router: router,
        logger: logger
    )
    return lambda
}

/// Build router
func buildRouter() throws -> Router<AppRequestContext> {
    let router = Router(context: AppRequestContext.self)
    // Add middleware
    router.addMiddleware {
        // logging middleware
        LogRequestsMiddleware(.info)
    }
    // Add default endpoint
    router.get("/") { _,_ in
        return "Hello!"
    }
    return router
}
