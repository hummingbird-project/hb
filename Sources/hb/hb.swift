//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import ArgumentParser
import Foundation

@main
struct HB: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "HB is for creating and managing hummingbird applications.",
        version: "0.5.0",
        subcommands: [
            InitCommand.self,
            WatchCommand.self,
        ]
    )
}
