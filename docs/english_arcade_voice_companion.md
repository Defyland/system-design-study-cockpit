# English Arcade local voice companion

The recommended `apple_codex` path is a local macOS companion. Start it from
the study-cockpit directory:

```sh
bin/english_arcade_voice_companion
```

It binds only to `127.0.0.1` on port `43129` by default. The process creates a
new high-entropy pairing secret in memory and prints it once to its terminal.
Paste that value into the Guided voice panel. The browser keeps the secret only
in tab `sessionStorage` under its pairing key; it is never placed in
`localStorage`, a URL, a request body, or a log. `ENGLISH_ARCADE_VOICE_COMPANION_PORT`
may choose another local port. `ENGLISH_ARCADE_VOICE_COMPANION_ORIGINS` is an
explicit comma-separated exact-origin allowlist; when omitted it is
`http://localhost:3000,http://127.0.0.1:3000`.

## Browser API

Every request below requires a matching `Origin` from the allowlist and the
`X-English-Arcade-Pairing` header. Responses are JSON, use `Cache-Control:
no-store` and `Vary: Origin`, and do not contain account identity or tokens.
`OPTIONS` is limited to an allowlisted origin and a documented path.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/v1/status` | Coarse companion, Apple, and Codex account state |
| POST | `/v1/login` | Starts managed ChatGPT browser login |
| POST | `/v1/speech/start` | Starts on-device Apple Speech capture |
| GET | `/v1/speech/status?capture_id=...` | Polls state and the temporary transcript |
| POST | `/v1/speech/stop` | Stops capture and returns its final temporary transcript |
| POST | `/v1/analyze` | Sends bounded visible card context/transcript to Codex |
| POST | `/v1/cleanup` | Stops capture and closes pending Codex work |

The status endpoint reports only `signed_out`, `login_pending`, `signed_in`, or
`unavailable` for Codex. Apple capture emits bounded state/transcript/error
records; raw audio never crosses the helper boundary and no transcript is
written to disk. The companion clears active child work on cleanup and process
exit.

## Codex boundary

Feedback uses only the official local command
`codex app-server --listen stdio://` and NDJSON JSON-RPC. The companion sends an
honest `initialize`/`initialized` handshake, `account/read`, and the managed
`account/login/start` form:

```json
{"type":"chatgpt","useHostedLoginSuccessPage":true,"appBrand":"chatgpt"}
```

It never reads `~/.codex/auth.json`, accepts an API key, implements device/OAuth
flows, or returns credentials. Initialization opts into the experimental API
capability. Before each analysis, the companion asks `permissionProfile/list`
for the empty temporary working directory and proceeds only when the exact
`:read-only` profile is returned as allowed. Each analysis then creates a fresh
`thread/start` with `ephemeral: true`, that cwd, `permissions: ":read-only"`,
and `approvalPolicy: "never"`; it sends neither the legacy `sandbox` nor
`sandboxPolicy` fields. It then starts a turn with model `gpt-5.6-luna`, effort
`max`, and a strict object schema for summary, clarity, fluency, pace, grammar,
relevance, cautious pronunciation, limitations, and a safe first-person
example. The companion waits for both authoritative `item/completed` and
`turn/completed`.
Read-only turns may emit normal intermediate `userMessage`, `reasoning`, and
`commandExecution` items; these are ignored from feedback. Only one matching
`agentMessage` plus a completed turn is accepted as the structured result.
Analysis has a 90-second default timeout; callers and deterministic tests may
inject a shorter bound. On timeout it sends `turn/interrupt` and terminates the app-server child.
An ephemeral thread is not sent to `thread/delete`, as the official protocol does
not permit deleting ephemeral roots; the empty temporary directory is removed
in `ensure`.

## Apple helper

`native/english_arcade_voice_companion/AppleSpeechHelper.swift` uses
`Speech` + `AVFoundation`, defaults to `en-US`, and sets
`requiresOnDeviceRecognition = true`. Unsupported on-device recognition and
denied microphone/speech permissions produce a clear bounded error; there is
no cloud fallback. `Info.plist` contains the required microphone and speech
usage descriptions.

The companion compiles the helper only on macOS and caches the executable in
the operating-system temporary directory using the Swift source hash. No
binary is generated in this repository. Tests inject a fake process and never
request microphone permission or start a paid provider call.

`openai_realtime` remains a separate, explicit Rails/WebRTC path. It is billed
to the OpenAI Platform account and is not included in a ChatGPT subscription.
