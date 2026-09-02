# Seeker Avatar art ships in the build, not from Storage

Every other piece of art in this game arrives at runtime from the server —
Anima sprite sheets land in `user://animas/`, chapter and Boss Seeker art come
out of the `chapter_assets` bucket — so bundling Seeker Avatar sheets into the
build looks inconsistent, and it is inconsistent on purpose. A keyed nine-pose
Seeker Sheet weighs about 0.8 MB, so a four-figure roster costs roughly 3.2 MB
on a 55 MB build, and paying those bytes deletes a bucket, an upload step, a
download path, and the failure mode where a player's own avatar is silently
missing from the arena because one fetch failed.

## Consequences

The roster stops being free to grow. Past roughly six figures the APK cost
overtakes the complexity it buys, and delivery should move to the
`chapter_assets` pattern that already exists for Boss Seekers. The code carries
a `ponytail:` comment naming that ceiling so the next reader knows this is a
measured trade, not an oversight.
