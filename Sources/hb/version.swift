//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

/// A struct representing a basic semver version.
public struct Version: Sendable {
    /// The major version.
    public let major: Int

    /// The minor version.
    public let minor: Int

    /// The patch version.
    public let patch: Int
    /// Creates a version object.
    public init(
        _ major: Int,
        _ minor: Int,
        _ patch: Int
    ) {
        precondition(major >= 0 && minor >= 0 && patch >= 0, "Negative versioning is invalid.")
        self.major = major
        self.minor = minor
        self.patch = patch
    }
}

extension Version {
    public init?<S: StringProtocol>(_ versionString: S) {
        let versionStringComponents = versionString.split(separator: ".", maxSplits: 3)
        guard versionStringComponents.count > 1 else { return nil }
        guard versionStringComponents.count < 4 else { return nil }

        var iterator = versionStringComponents.makeIterator()

        guard let majorString = iterator.next(), let major = Int(majorString) else { return nil }
        guard let minorString = iterator.next(), let minor = Int(minorString) else { return nil }

        self.major = major
        self.minor = minor

        if let patchString = iterator.next() {
            guard let patch = Int(patchString) else { return nil }
            self.patch = patch
        } else {
            self.patch = 0
        }
    }
}

extension Version: Comparable, Hashable, Equatable {
    public static func < (lhs: Version, rhs: Version) -> Bool {
        let lhsComparators = [lhs.major, lhs.minor, lhs.patch]
        let rhsComparators = [rhs.major, rhs.minor, rhs.patch]

        return lhsComparators.lexicographicallyPrecedes(rhsComparators)
    }

    // Custom `Equatable` conformance leads to custom `Hashable` conformance.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.major)
        hasher.combine(self.minor)
        hasher.combine(self.patch)
    }
}

extension Version: CustomStringConvertible {
    public var description: String {
        "\(major).\(minor).\(patch)"
    }
}
