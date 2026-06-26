//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import Noora

struct NoWhitespaceValidationRule: ValidatableRule {
    let error: any ValidatableError

    func validate(input: String) -> Bool {
        !input.contains(where: \.isWhitespace)
    }
}

struct AsciiValidationRule: ValidatableRule {
    let error: any ValidatableError

    func validate(input: String) -> Bool {
        !input.contains(where: { !$0.isASCII })
    }
}

struct SwiftTargetValidationRule: ValidatableRule {
    static let characters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
    let error: any ValidatableError

    func validate(input: String) -> Bool {
        !input.contains(where: { !Self.characters.contains($0) })
    }
}
