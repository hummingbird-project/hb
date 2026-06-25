//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import Mustache

/// A context value can be either a string or an array of strings
enum ContextValue: MustacheCustomRepresentation, Equatable {
    case string(String)
    case array([String])

    var representation: Any? {
        switch self {
        case .string(let string): string
        case .array(let array): array
        }
    }
}

/// The context is a map of string keys to context values
typealias Context = [String: ContextValue]
