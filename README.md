# Shadow43

A visionOS app for Apple Vision Pro that shows the three-dimensional shadow (projection) of
four-dimensional objects, such as the tesseract, the 120-cell, the Klein bottle and the Hopf
fibration. You can rotate them in all six 4D rotation planes, by hand or automatically, and morph
continuously between orthographic, perspective and stereographic projection.

Status: early development. See [DESIGN.md](DESIGN.md) for the full design.

## Build

Requirements: Xcode 27.1 or later with the visionOS 27 SDK, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate                        # creates Shadow43.xcodeproj from project.yml
swift test --package-path Packages/Core4D
open Shadow43.xcodeproj
```

To run the app on your own device, create `Config/Signing.local.xcconfig` (it is git-ignored):

```
DEVELOPMENT_TEAM = <your team ID>
PRODUCT_BUNDLE_IDENTIFIER = <your unique bundle ID>
```

## License

Apache License 2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE). © 2026 Andreas Keese.
