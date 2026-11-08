// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Core4D
import Foundation
import os
import SwiftUI

/// Keeps the settings between launches in the user defaults (D29).
enum SettingsStore {
    static let logger = Logger(subsystem: "Shadow43", category: "Settings")
    private static let key = "savedSettings"

    /// The saved settings, or nil if there are none or they cannot be read at all.
    static func load() -> SavedSettings? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        do {
            return try SavedSettings.decode(data)
        } catch {
            logger.error("Saved settings (\(data.count) bytes) could not be read, using the defaults: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func save(_ settings: SavedSettings) {
        do {
            UserDefaults.standard.set(try settings.encoded(), forKey: key)
        } catch {
            logger.error("Settings could not be saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Saves the settings half a second after the last change, and at once when the volume leaves the
/// foreground (D29). It is its own view so that only it, not the volume, is re-evaluated while
/// the motion changes every frame (friction).
struct SettingsSaver: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var pending: Task<Void, Never>?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: model.savedSettings) { _, settings in
                guard model.persistsSettings else { return }
                pending?.cancel()
                pending = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    if !Task.isCancelled { SettingsStore.save(settings) }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase != .active, model.persistsSettings else { return }
                pending?.cancel()
                SettingsStore.save(model.savedSettings)
            }
    }
}
