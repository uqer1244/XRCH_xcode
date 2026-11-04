# Security and public development

This repository contains a development prototype, not a security-hardened location transport.
Do not commit credentials, user sessions, private signing material, or real location logs.

## Client configuration

Copy `Config/LocalSecrets.xcconfig.example` to the ignored
`Config/LocalSecrets.xcconfig` and supply your own project settings. A fresh clone does
not default to the original production Supabase project. Missing configuration fails
before authentication/network requests. MapKit discovery is independent of Supabase.

The Supabase anon/publishable key is **public client configuration**, even when kept in
an ignored local file. It is embedded in the app and can be extracted. Never substitute
a service-role key, a Supabase secret key, a JWT signing secret, or a GPU worker secret.
`AUTH_TESTING` is reserved for standalone offline tests and must not be added to app
build settings.

Removing configuration from the latest source does not remove previous versions from
Git history. The earlier committed Supabase key was an `anon` key, not a service-role
key. The old project endpoint and public key must still be treated as publicly known.

## Backend requirements

These are deployment requirements, not guarantees provided by the iOS code:

- Enable and test RLS for every client-accessible table.
- Enforce profile ownership, including access to `profiles.api_key` used by the legacy
  compatibility path. Never allow reading another user's key.
- Verify JWT identity and authorization in every Edge Function.
- Enforce GPU quota and rate limits on the server, not only in UI state.
- Protect anonymous signup against repeated-account abuse; a per-user daily allowance
  alone is insufficient to cap infrastructure spending.
- Keep worker/service credentials on the server and impose infrastructure spending limits.

A source review of this app does not verify the deployed policies or functions.

## Session storage and diagnostics

Access and refresh tokens use Keychain with `WhenUnlockedThisDeviceOnly`. They are not
written to UserDefaults. Offline authentication tests use in-memory storage and a mock
URL protocol, not the real Keychain or Supabase.

AI diagnostic logging is disabled in Release. Debug AI logs omit request/response
bodies, question text, and GPS coordinates. Inspect any diagnostics before sharing;
separate device diagnostics can still display location packets. Never publish those
screenshots or exports with real personal locations.

## Location transport limitations

- BLE discovery currently trusts the first advertiser of the configured service UUID.
  A UUID is an identifier, not authentication. Confirm receiver identity and implement
  pairing/device authorization before deployment in untrusted environments. Link-level
  encryption also depends on the Quest receiver's characteristic permissions.
- UDP location packets currently use ordinary UDP without application-level encryption
  or message authentication. Restrict this development path to trusted networks. Do not
  use it for sensitive location transmission over public networks.
- The app's “sent” state is not proof that the recipient rendered a POI. Receiver
  acknowledgements and stronger delivery guarantees are separate protocol work.

These transport contracts were not changed as part of the public-repository cleanup.

## Before publishing changes

1. Review the complete staged diff, including untracked files and build settings.
2. Confirm `Config/LocalSecrets.xcconfig`, `.env*`, `xcuserdata`, certificates, archives,
   and diagnostic exports are ignored and not already tracked.
3. Run the offline tests documented in `README.md` and build Debug and Release.
4. Inspect Git history with a secret scanner. If a real secret ever enters history,
   revoke/rotate it first; deleting the current file or rewriting history alone is not
   sufficient.
5. Do not post tokens, private keys, or real location traces in GitHub issues. Use a
   private security advisory if enabled, or contact the maintainer privately.
