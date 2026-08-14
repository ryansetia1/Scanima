# DeeplinkPlugin

- Source: https://github.com/godot-mobile-plugins/godot-deeplink
- Release: `v5.3`
- Archive: `DeeplinkPlugin-Multi-v5.3.zip`
- SHA-256: `22d7deca3649efa3b51438bcaaeba2cdd691415f7931b3788f4d577f363eb0be`
- Compatibility target: Godot 4.6 Android and iOS

Scanima registers `scanima://auth/callback` for Supabase PKCE callbacks.

Local patch: the iOS export hook now returns early during Android exports. The
upstream v5.3 hook otherwise logs `Unexpected export path ...apk` after a
successful Android build. Reapply this guard when upgrading the plugin.
