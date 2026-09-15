# List & Split mark

Original shared-checklist design, generated with the available image tool and
finished as reproducible vector geometry. The gold `#F4AE45` and charcoal
`#202020` come from the existing app palette. No text is embedded in the icon.

`lib/core/branding/list_split_mark.dart` is the geometric source used by Flutter.
Run `flutter test tools/branding/generate_branding_test.dart` to regenerate the
SVG, preview, Android adaptive/monochrome vectors and five legacy PNG densities.
The graphic remains inside the adaptive-mask safe area. The monochrome resource
contains the mark only, with no background plate. `design-concept.png` retains
the original generated design reference; it is not bundled in the APK.

The native charcoal splash and the Flutter welcome use the same mark/palette.
Android 12+ uses the system splash; older versions use a centered vector drawable.
The normal launch cover lasts about three seconds while initialization runs. An
incoming destination or reduced motion bypasses the cover; resume does not replay.
