# App icon

The source is `App/Groceries.icon`, a native layered Icon Composer document. The supplied concept is an inspiration for the color and shopping bag silhouette; the artwork here is original vector geometry.

## Construction

- Keep the shared 1024 × 1024 coordinate system in every SVG. Leave the platform corner mask and border to the system.
- The canvas owns the emerald gradient, with a darker appearance variant. The three depth groups contain the leaf and banana, tomato, and translucent bag front. This keeps the silhouette readable at Home Screen size.
- Source SVGs contain flat colors and simple shapes. Icon Composer provides the glass translucency, blur, specular lighting, and shadows. Don't paint static reflections into the source layers.
- The bag is the largest shape and the clearest mono silhouette. Preview default, dark, tinted, and clear variants and the circular crop in Icon Composer before shipping. If mono contrast is weak, tune the group's mono appearance there.
- The JSON document is wired to Xcode through `ASSETCATALOG_COMPILER_APPICON_NAME: Groceries` in `project.yml`.

## Sources

- [Apple: Create icons with Icon Composer (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/361/)
- [Apple: Say hello to the new look of app icons (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/220/)
- [Apple: Icon Composer](https://developer.apple.com/icon-composer/)

The icon's rendered glass treatment must be checked on an Apple device or Mac build; a plain SVG composite is not a faithful Icon Composer preview.
