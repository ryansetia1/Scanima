# Chapter Factory — Zone Background Art

Generate one opaque 16:9 landscape PNG (~768×432 or a larger exact 16:9) for an
Expedition combat arena. This image is the Battle backdrop, not a node-map
illustration.

Style lock — match the chapter's Anima and Boss Seeker:
- original 2D anime cel-shaded environment; large readable shapes first
- four to six major flat colors, dark charcoal or plum contours, one hard
  cel-shadow, restrained highlights
- texture only as a few large material accents, never grain, sparkle, or
  repeated micro-detail across the frame
- keep the center quiet so fighters stay the focus after mobile downscale

Combat floor — required:
- the lower 30–35% is one continuous solid floor plane (tile, slab, packed
  court, or platform) wide enough for two fighters and a Boss Seeker
- the bottom 15–20% must stay unbroken across the center 50–60% of the width
- no liquid, lava, syrup, rails, gutters, chasms, vents, fences, or props
  under the fighter foot line
- spectacle (vats, silos, furnaces, gates) stays in the upper/mid background
  behind a clear floor edge or low wall

Composition:
- center-weighted: tall phones crop the left and right edges
- keep the top ~25% simple (sky, horizon, or quiet architecture) for HUD
- leave the right-third lower band uncluttered for the Boss Seeker silhouette
- no characters, creatures, text, logos, sign lettering, watermark, UI, or
  recognizable IP landmarks

Forbidden: photoreal or PBR rendering, glossy 3D, airbrush gradients, bloom,
glow, steam/particle haze, crystalline sparkle carpets, and AI-detail soup.

Do not auto-retry failed generations.
