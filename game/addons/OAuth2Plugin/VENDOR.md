# OAuth2Plugin

- Source: https://github.com/godot-mobile-plugins/godot-oauth2
- Release: `v1.1`
- Archive: `OAuth2Plugin-Multi-v1.1.zip`
- SHA-256: `44003b8af1c251e343cff06a1d35b3a41bf1bbfabcee5d564ba64f22379d380f`
- Compatibility target: Godot 4.6 Android and iOS

The native singleton also supplies encrypted token storage: Android uses an
AES-GCM key in Android Keystore; iOS uses Keychain.

## Local Android manifest patch

Scanima uses the native singleton for secure token storage and drives PKCE over
its existing `Backend`; the AAR contains no AndroidX class references.

- Removed unused `ACCESS_NETWORK_STATE` from both AAR manifests.
- Removed the template AppCompat dependency from `OAuth2Plugin.gd`, avoiding
  unrelated AndroidX startup components and permissions.
- Debug AAR SHA-256:
  `60de8da871796c1e4dafa1b459377235a4256f1c0755edd5ea17a89d076a01f3`
- Release AAR SHA-256:
  `67bdd787e02b835427b571832fb2989a1722880f726174022ef5d09ec5b1b6c3`

Reapply and re-verify this patch when upgrading the vendored release.
