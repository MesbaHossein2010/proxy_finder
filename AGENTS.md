# Proxy Finder — Project Rules & Team

This file tells every agent session how to work on this repo.
Read it first. Follow it.

## Repo identity

- App name: **Proxy Finder**
- Package: `com.mesbahossein.proxychecker`
- GitHub: `MesbaHossein2010/proxy_finder` (public)
- Author / single user: **Mesbah** (Iran; Telegram + Bale)
- Target device: XiaoMi Mi 10, HyperOS / Android 13 (SDK 33)

## Delivery model (do NOT change)

- **APK is built by GitHub Actions on every push to `main`.**
- Permanent download link (ZIP):
  `https://github.com/MesbaHossein2010/proxy_finder/releases/download/latest/proxy-finder-latest.apk.zip`
- Permanent releases page:
  `https://github.com/MesbaHossein2010/proxy_finder/releases/latest`
- Release tag is always `latest`. CI deletes and re-creates it each build.
- Send the user **both** the ZIP link and the releases-page link on every
  successful build. Never send a raw .apk hash or artifact id.
- The user must **uninstall old installs** before installing a new APK.

## The team (who does what)

This repo is run by a small team. Roles are fixed. Do not blur them.

- **Claude (AI adviser)** — reviews designs, gives a second opinion, checks the
  repo online, catches blind spots. He does not push code.
- **Agent007 (executor / master)** — the agent running in Hermes. Plans, edits
  code, pushes via test scripts, monitors CI, reads CI logs, sends Telegram
  updates. This is usually "you".
- **GitHub Actions (validator)** — the only place builds/tests run. It runs on
  GitHub runners, never locally. Zero data cost to the user.
- **Telegram / Bale (delivery)** — how the user gets build links and status.
- **The user (Mesbah)** — decides. Always explain the issue, never just state
  a presumed cause.

Related rule: the user's larger skill set names roles "uiux", "logic",
"security", "research", "executor". When a task is pure implementation,
build and publish, it belongs to **executor**. Use the smallest team node
that can finish the task. Do not spawn the whole team for small work.

## Non-negotiable rules

1. **No repo clone.** Push exclusively through the local push script
   (`push_api.sh`, GitHub Contents API) through the local VLESS tunnel.
2. **Zero data cost to the user.** All builds (analyze + build + emulator
   test) run on GitHub Actions runners, never locally. The user is on a
   1 GB metered budget. Do not download SDKs or clone big repos locally.
3. **No local Flutter.** There is no Flutter binary here. Validate by reading
   code, checking brace/syntax balance, greps. Real validation is CI.
4. **No secrets in files.** Tokens, GH_TOKEN, VLESS keys are never written to
   the repo. In chat and logs, print secrets as `[REDACTED]`.
5. **Secrets/config in env.** Keep `GH_TOKEN` and API keys in environment
   variables or the agent's memory, not in the codebase.
6. **Never delete user files/folders without written confirmation.**
7. **Always give an estimated time before starting each task.** State the
   estimate, then start work after the user confirms the plan.
8. **Every change must be checked before pushing.** Re-read the push script
   `CHANGED` list: every new or modified file MUST be listed there, or the
   build silently breaks (unresolved class errors). This is a recurring trap.
9. **The plugin is vendored.** Never run `script.sh`; it would overwrite the
   patches. `packages/flutter_sing_box_patched` is a patched copy of
   `clash-sing/flutter_sing_box`.
10. **Collaborate with Claude when the user asks.** Use the browser session to
   discuss. Share the repo URL so he can check it online. Bring his review
   back before finalizing big fixes.
11. **Collaborate with the user's real device.** Real-device test results come
    from Mesbah's Mi 10, not the emulator. The emulator catches UI/launch
    crashes only; VPN runtime is only real on the device.

## Coding rules

- Fiction the user rejects: do not tell the user to change their phone
  settings. Other VPN apps work on this device — the bug is in our code.
- Root cause chain (learned, do not regress):
  1. VPN consent dialog did not appear on HyperOS. Cause: the Dart →
     MethodChannel → plugin → `startActivity` hop loses the "user gesture"
     signal, so HyperOS's background-launch blocker swallows it.
     Fix: a transparent native `VpnPermissionActivity` whose `onCreate`
     calls `VpnService.prepare(this)` + `startActivityForResult`
     synchronously (same call stack, zero hops), like v2rayNG/WireGuard.
  2. After consent, crash `ExceptionInInitializerError ... MMKV.initialize
     not called`. Cause: `MMKV.mmkvWithID()` ran before `MMKV.initialize()`
     in the `:remote` VPN service process. Fix: an `Application` subclass
     (`ProxyFinderApp`) calls `MMKV.initialize()` in every process,
     unconditionally. Do not gate it behind a process-name check.
     The app module cannot `import com.tencent.mmkv.MMKV` directly
     (plugin-only dep) — route through `PluginManager.initializeMmkv()`.
  3. Second run crash `SERVICE_RELOAD_FAILED ... command.sock: no such file`.
     Cause: HyperOS killed the background VPN; Dart's `_vpnStarted` bool
     still said true, so the app reloaded a dead socket. Fix: catch the
     reload error, and only restart for dead-service messages
     (`no such file or directory`, `DeadlineExceeded`, `connection error`);
     rethrow config errors so they surface.
- Emulator quirks: default 2 GB AVD RAM OOM-kills app + sing-box + Go
  runtime. Use `-memory 4096`. On failures dump BOTH logcat and kernel
  dmesg (OOM shows in kernel log, not app logcat) BEFORE the final alive
  check. KEYCODE_BACK dismisses (does not confirm) a dialog. Stock AVD
  images do NOT auto-grant VPN consent.
- Keep English for app-facing strings. User communicates in English here
  (he is Farsi-speaking but works in this repo in English).
- Point out the user's spelling/grammar/typo mistakes in chat and code.
  Never point out capitalization.
- Prefer modern dark aesthetics. No Chinese-themed design. Rich visual
  analytics (charts/tables), not bare data. Call out RTL/LTR errors.
- Replies follow Simplified Technical English (ASD-STE100): short
  sentences, active voice, approved words, no idioms.

## Push / CI workflow

1. Edit code. Add every changed/new file to the `CHANGED` list in
   `push_api.sh` if it is not already there.
2. Push with a **rational commit message**:
   `bash push_api.sh <dir> "fix: restart dead VPN service on reload"`
   Use conventional prefixes: `fix:`, `feat:`, `chore:`, `docs:`, `refactor:`.
3. CI runs 4 jobs in order: Analyze & Test → Build APK → Emulator Smoke
   Test → Publish APK to Release. The release step reads the commit message
   into the release notes and the app version into the title.
4. Monitor CI via the GitHub API (through the tunnel). On failure, pull the
   exact job log line that names the error before fixing. Do not guess.
5. On green, Telegram the user both links + a short milestone note.
6. The tunnel is sing-box (VLESS). Its SOCKS listen port can change;
   detect it with `ss -tlnp | grep sing-box` rather than assuming 2080.
   Currently: 1080.

## Contact / delivery

- Telegram chat_id `8860010403`, bot `BrightHermesAgent007bot`.
- Egress for GitHub API and Telegram goes through the local sing-box SOCKS
  tunnel. GitHub API is blocked without it.
- On big projects, send Telegram progress: start + milestones + completion.
