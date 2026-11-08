// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import RealityKit

/// Marks the entity whose touches turn and scale the object (variant A gestures). The gestures
/// target only it, so other touchable entities, such as the room's floor disc that moves the
/// object (D33), do not also rotate it.
struct ShadowInputComponent: Component {}
