# Windows Preview 3: bounded final corrections

This candidate is local and unpublished. The approved public commit and R1
artifacts remain unchanged. Windows is the only platform under validation;
Linux and macOS remain in development.

The Preview 2 trial confirmed 35m35s of continuous authentication, four logins,
three voluntary logouts, 354 fully correlated rendered heartbeats and normal
shutdown. It did not prove heartbeat reactivation after the last login.

Confirmed corrections:

- Pubkey requests stop on session invalidation, reject old-generation results,
  and release only their own per-asset claim. Three failing reproductions cover
  cancellation, late success and late failure across logout.
- NFT synchronization failure no longer becomes a successful empty cache.
  A bounded, coalesced capability check uses the existing HTTPS provider and
  a fixed public zero identifier. It sends no wallet address or credentials,
  follows no redirects and retains normal TLS validation. Invalid/missing
  `result`, the provider's disabled message and transport/deadline failures
  produce an explicit unavailable state. This check does not certify that a
  wallet's NFT cache is synchronized; successful KDF synchronization is still
  required.
- The isolated diagnostic panel reserves footer space and clears stale state
  and the visual counter on authentication changes. Every invocation and
  refusal has a fixed category. Requests include session epoch and registered
  connection metadata; heartbeat frames retain their original six-stage trace.
  Acknowledgements never increment the visual counter. One uncertain request
  per authenticated session remains enforced.

The historical final-click failure is not retrospectively attributed to the
transport: Preview 2 lacked an invocation record and did not log one duplicate
session branch. The new loopback regression proves real delivery across three
session replacements; an equivalent disposable KDF trial is still required.

History HTTP 500, other RPC failures and catalogue exclusions remain separately
tracked. No replacement providers, insecure TLS, engine modifications, fee
changes, network changes or new trading functionality are introduced.

Distribution remains blocked pending the real candidate trial, KDF licence
review and actual required notification, authorized motor availability,
remote native build and a clean-Windows test. A notification draft is not a
delivered notice. No release, tag, binary upload or push is authorized here.
