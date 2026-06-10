//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import Subprocess

struct SubprocessCommand {
    let executable: Executable
    let arguments: Arguments

    init(_ executable: Executable, arguments: Arguments) {
        self.executable = executable
        self.arguments = arguments
    }

    init(_ executable: Executable, arguments: [String]) {
        self.executable = executable
        self.arguments = .init(arguments)
    }
}
