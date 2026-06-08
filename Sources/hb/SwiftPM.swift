import Subprocess

#if canImport(System)
import System
#else
import SystemPackage
#endif

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct SwiftPM {
    let useSwiftly: Bool

    func getCommand(_ arguments: [String]) -> SubprocessCommand {
        if self.useSwiftly {
            return .init(.name("swiftly"), arguments: .init(["run", "swift"] + arguments))
        } else {
            return .init(.name("swift"), arguments: .init(arguments))
        }
    }

    func getBinaryPath(product: String) async throws -> FilePath {
        let command = getCommand(["build", "--show-bin-path"])
        let output = try await Subprocess.run(
            command.executable,
            arguments: command.arguments,
            output: .string(limit: 1_000_000)
        )
        guard var standardOutput = output.standardOutput?[...] else { throw HBError("Failed to get binary path") }
        while standardOutput.last?.isNewline == true {
            standardOutput = standardOutput.dropLast()
        }
        var path = FilePath(String(standardOutput))
        path.append(product)
        return path
    }

    func getExecutableProducts() async throws -> [String] {
        struct Package: Decodable {
            enum ProductType: Decodable {
                case library
                case executable
                case unknown

                init(from decoder: any Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    if container.contains(.executable) {
                        self = .executable
                    } else if container.contains(.library) {
                        self = .library
                    } else {
                        self = .unknown
                    }
                }

                private enum CodingKeys: CodingKey {
                    case library
                    case executable
                }
            }
            struct Product: Decodable {
                let name: String
                let type: ProductType
            }
            let products: [Product]
        }
        let command = getCommand(["package", "describe", "--type", "json"])
        let output = try await Subprocess.run(
            command.executable,
            arguments: command.arguments,
            output: .string(limit: 1_000_000)
        )
        guard let standardOutput = output.standardOutput?[...] else { throw HBError("Failed to get package description") }
        do {
            let swiftPackage = try JSONDecoder().decode(Package.self, from: Data(standardOutput.utf8))
            return swiftPackage.products.compactMap {
                guard $0.type == .executable else { return nil }
                return $0.name
            }
        } catch {
            throw HBError("Failed to get executable target names.")
        }
    }

    func getExecutableProduct(desiredProduct: String?) async throws -> String {
        let executables = try await self.getExecutableProducts()
        let targetProduct: String
        if let product = desiredProduct {
            guard executables.contains(product) else {
                throw HBError("Cannot find executable target \(product)")
            }
            targetProduct = product
        } else {
            guard executables.count != 0 else {
                throw HBError("Package has no executables products.")
            }
            guard executables.count == 1 else {
                throw HBError("Package has multiple executables. Please use \"--product\" to choose the executable you want to run.")
            }
            targetProduct = executables[0]
        }
        return targetProduct
    }
}
