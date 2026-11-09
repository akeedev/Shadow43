// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Core4D
import SwiftUI

/// The content of the info window below the controls (D22, D25, D40): the About page, or the
/// explanation of the control last tapped in "?" mode. An explained object is shown in the
/// volume itself (see `HelpTarget`).
struct HelpPanel: View {
    /// Size of a new info window; the user can make it larger.
    static let defaultSize = CGSize(width: 620, height: 820)

    @Environment(AppModel.self) private var model

    var body: some View {
        let topic = model.helpTopic ?? .about
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text(topic.title).font(.largeTitle)
                Spacer()
                Button("Close", systemImage: "xmark") { model.closeHelp() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
            }
            if topic == .about {
                AboutContent()
            } else {
                ScrollView {
                    Text(topic.text)
                        .font(.title3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        // The window draws the glass; its minimum size is this view's minimum (D25).
        .padding(32)
        .frame(minWidth: 480, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity,
               alignment: .topLeading)
    }
}

/// Marks a control as a help target: in "?" mode a tap explains it instead of using it. Taps that
/// only change what is shown still take effect: explaining an object also shows it in the volume,
/// which depicts it, and explaining a tab opens it (D22, D46).
struct HelpTarget: ViewModifier {
    @Environment(AppModel.self) private var model
    let topic: HelpTopic

    func body(content: Content) -> some View {
        content.overlay {
            if model.isHelpMode {
                let isShown = model.helpTopic == topic
                Button {
                    model.explain(topic)
                } label: {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(isShown ? 0.25 : 0.05))
                        .strokeBorder(Color.accentColor.opacity(isShown ? 1 : 0.6),
                                      style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .contentShape(.rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(-4)
            }
        }
    }
}

extension View {
    /// See `HelpTarget`.
    func helpTarget(_ topic: HelpTopic) -> some View {
        modifier(HelpTarget(topic: topic))
    }
}

/// About page: who, version, build date, and how to use the app.
struct AboutContent: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// When the app was built: the date of its executable, so it never goes stale (D51).
    private static let buildDate: Date? = {
        guard let path = Bundle.main.executablePath,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return attributes[.modificationDate] as? Date
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("The 3D shadows of 4D objects.").font(.title3)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Version \(version)")
                    if let date = Self.buildDate {
                        Text("Built on \(date.formatted(date: .long, time: .omitted))")
                    }
                    Text("By Andreas Keese with Claude")
                    Text("Open source under the Apache License 2.0")
                }
                .foregroundStyle(.secondary)

                Text("How to use").font(.title)
                ForEach(Self.usage.indices, id: \.self) { i in
                    let item = Self.usage[i]
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.headline)
                        Text(item.text)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct UsageItem {
        let title: LocalizedStringKey
        let text: LocalizedStringKey
    }

    private static let usage: [UsageItem] = [
        UsageItem(title: "Move the window",
                  text: "Look at the small bar below the window, pinch, and move your hand. The Controls and this Info panel have bars of their own."),
        UsageItem(title: "Close the app",
                  text: "Close the window or the Controls; everything else closes with it."),
        UsageItem(title: "Resize the window",
                  text: "Look at one of the window's bottom corners until a handle appears, then pinch and drag."),
        UsageItem(title: "Rotate in 4D",
                  text: "Pinch on the object and drag. Left and right turn x into w, up and down turn y into w, towards you and away turn z into w."),
        UsageItem(title: "Throw and catch",
                  text: "Let go while your hand is still moving and the object keeps spinning. Pinch and hold to stop it."),
        UsageItem(title: "Rotate in 3D",
                  text: "Pinch with both hands and twist."),
        UsageItem(title: "Change the size",
                  text: "Pinch with both hands and move them apart or together, or use Display → Size."),
        UsageItem(title: "Back to the start",
                  text: "Double-tap the object, or Motion → Reset. Reset all puts every setting back."),
        UsageItem(title: "Help",
                  text: "Tap ? and then any control to read what it does. Tap ? again to leave help mode."),
    ]
}
