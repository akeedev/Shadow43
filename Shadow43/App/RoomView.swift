// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// Content of the immersive space (experimental in v1): the same content at room scale.
/// The controls stay in the window's ornament.
struct RoomView: View {
    static let spaceID = "room"

    @Environment(AppModel.self) private var model

    var body: some View {
        ShadowRealityView(host: .room)
            .onDisappear { model.isRoomOpen = false }
    }
}
