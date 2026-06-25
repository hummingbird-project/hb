//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import Mustache

/// A context value can be either a string or an array of strings
enum ContextValue: MustacheCustomRepresentation, Equatable, Decodable {
    case string(String)
    case array([ContextValue])
    case map([String: ContextValue])

    var representation: Any? {
        switch self {
        case .string(let string): string
        case .array(let array): array
        case .map(let map): map
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([ContextValue].self) {
            self = .array(array)
        } else if let map = try? container.decode([String: ContextValue].self) {
            self = .map(map)
        } else {
            throw DecodingError.typeMismatch(
                ContextValue.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Failed to decode ContextTransformGroup")
            )
        }
    }
}

/// The context is a map of string keys to context values
typealias Context = [String: ContextValue]
