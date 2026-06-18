//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

struct HBError: Error, CustomStringConvertible, Equatable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String { self.message }
}
