# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.2.x   | Yes       |
| 0.1.x   | No        |

Security fixes are released on the latest 0.x minor only. Upgrade to 0.2.x to
receive patches.

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Report privately via
[GitHub Security Advisories](https://github.com/Ranveer-Singh-Gour/air_pointer/security/advisories/new).
Include:

- A clear description of the vulnerability and its impact
- Reproduction steps (minimal sample code where possible)
- Suggested mitigation if you have one

You can expect an acknowledgement within 5 business days and a status update
within 14 days.

## Scope

This package is a pure client-side Flutter plugin. It contains no server-side
code, no authentication, and no persistent storage. The primary security-relevant
surfaces are:

| Surface | Notes |
|---------|-------|
| Camera access (`getUserMedia`) | Requires explicit user permission; the package does not store or transmit video frames |
| MediaPipe CDN (`cdn.jsdelivr.net`, `storage.googleapis.com`) | Assets are loaded at runtime; self-hosting is supported — see README |
| `hand_tracker_worker.js` | Must be served from the same origin as `index.html` to satisfy browser CORS policy |

CDN availability and integrity are outside the scope of this package's security
policy. If you are operating in a high-security environment, self-host the
MediaPipe WASM bundle and model using the `mediaPipeBaseUrl` and `modelAssetUrl`
constructor parameters.

## Disclosure Policy

Once a fix is released, vulnerabilities will be disclosed publicly via a GitHub
Security Advisory. The disclosure timeline will be agreed with the reporter, but
will not exceed 90 days from the fix being available.
