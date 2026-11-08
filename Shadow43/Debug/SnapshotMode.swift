// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Core4D
import Foundation
import os

/// Snapshot mode (DESIGN 6.9): launch arguments such as `-object tesseract -time 1.5` arrive in
/// the `UserDefaults` argument domain and are turned into a `ViewState`.
/// See `LaunchConfiguration` in Core4D for the recognised keys.
enum SnapshotMode {
    static let logger = Logger(subsystem: "Shadow43", category: "SnapshotMode")

    /// The launch arguments as a key → string dictionary.
    static func launchArguments() -> [String: String] {
        let domain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var result: [String: String] = [:]
        for (key, value) in domain {
            result[key] = (value as? String) ?? "\(value)"
        }
        return result
    }

    static func launchConfiguration() -> LaunchConfiguration {
        LaunchConfiguration.parse(launchArguments())
    }

    /// Whether `-room 1` asks to open the immersive space at launch.
    static var opensRoomAtLaunch: Bool { launchConfiguration().opensRoom }

    static func log(_ config: LaunchConfiguration) {
        if !config.problems.isEmpty {
            logger.error("Ignored launch arguments with unknown values: \(config.problems.joined(separator: ", "), privacy: .public)")
        }
        if let t = config.time {
            logger.info("Snapshot mode: time frozen at t = \(t, privacy: .public) s")
        }
    }
}
