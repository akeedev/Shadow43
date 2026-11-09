// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// Content of the immersive space: the same content at room scale, level in front of the viewer
/// (D30, D36). The controls stay in their own window (D25); the volume shows nothing while the
/// room is open.
struct RoomView: View {
    static let spaceID = "room"

    @Environment(AppModel.self) private var model

    var body: some View {
        ShadowRealityView(host: .room)
            .onDisappear { model.isRoomOpen = false }
    }
}
