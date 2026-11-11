# The remote emulator

A Windows PC on the LAN runs an x86_64 emulator, and it is the default device for
`test.sh`, `run.sh`, `install-apk.sh`, `logs.sh` and `debug.sh`. It keeps the Mac's
4 GB emulator off, and you drive the app with the PC's own mouse and keyboard, in the
emulator window on its desktop. What the x86_64 default misses, and the arm64 run a
release still needs, is in [build-and-run.md § Architecture
coverage](build-and-run.md#architecture-coverage).

## Using it

```
export FA_REMOTE_EMULATOR_HOST=my-pc   # in ~/.zshrc: an ssh alias, key auth
Scripts/Android/test.sh               # Android device: my-pc (x86_64)
Scripts/Android/run.sh --local        # this Mac's emulator instead
```

`--local` forces this host, `--remote` the PC; without the PC, the scripts say why and
use this host. `Scripts/Android/android-target.sh` picks, and
`Scripts/Android/remote-emulator.sh` (`up`, `down`) does the wiring: an ssh tunnel
makes the PC's emulator a TCP device of **this Mac's** adb server, `127.0.0.1:15555`, so
`adb forward`, LLDB and Gradle work as with a local device. The PC's own adb server
stays attached to the same adbd without trouble.

Never on the PC, by design: `profile.sh` and `run.sh --profile` (the timings would
measure the PC), `check-crash-reporting.sh` (it verifies the arm64 build) and
`start-emulator.sh`.

Each worktree's debug app needs its own FA login on the PC too, as on any emulator.

## The PC, as set up

Windows, Intel, S3 sleep only. Everything under the user account; the SDK is
`%LOCALAPPDATA%\Android\Sdk`.

- **JDK 17** and the **cmdline-tools**. This `sdkmanager` wants `a/b/c` package paths,
  not `a;b;c`.
- Image `system-images;android-37.1;google_apis_ps16k;x86_64` (16 KB pages, as on the
  Mac), and platform-tools at the Mac's adb version (37.0.1 both), since both adb
  servers talk to the one adbd.
- **AEHD** for acceleration. Its `silent_install.bat` silently does nothing over SSH;
  install it by copying `aehd.sys` to `C:\Windows\System32\drivers` and
  `sc create aehd type= kernel binPath= …\aehd.sys start= auto`, `sc start aehd`.
- AVD **`fa-x86`**, `hw.cpu.ncore=8` (the guest sees 6).
- The emulator starts from a scheduled task, **`FAEmulator`**, run as the user with
  `/it` (interactive only): that puts it in session 1, the desktop, with the host GPU
  and its window on screen. An SSH login is session 0, which has no GPU, and whatever
  it starts dies with the SSH session. The task's default 72 h limit stops the emulator
  after three days; the next `up` starts it again.
- The task runs `%USERPROFILE%\fa-emulator.cmd`:

  ```
  @echo off
  rem adb spawned by the emulator inherits this log handle and outlives it, so each run gets its own file.
  set LOG=%USERPROFILE%\fa-emulator-logs\%RANDOM%%RANDOM%.log
  mkdir "%USERPROFILE%\fa-emulator-logs" 2>nul
  "%LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe" -avd fa-x86 -no-audio -no-boot-anim -gpu host -memory 4096 %* > "%LOG%" 2>&1
  ```

  One log per run because the adb server the emulator spawns inherits its stdout handle
  and outlives it: the next run's `> same.log` then fails, the task reports result 1,
  and no emulator starts.
- No monitor is needed, for tests or the host GPU.
- **Sleep**: the power plan sleeps after 3 h idle on AC. The Wi-Fi adapter is armed for
  wake (`powercfg /deviceenablewake "Broadcom 802.11ac Network Adapter #2"`;
  `powercfg /devicequery wake_armed` lists it), and `FA_REMOTE_EMULATOR_WAKE_MAC` set to
  its MAC lets `up` wake it.

## Speed

Measured 2026-11-11, `test.sh` wall time:

| Device | Wall | FAKit suite |
|---|---|---|
| Mac, arm64 emulator | ~39 s | 3.4 s |
| PC, x86_64 native | ~51 s | 10.2 s |
| PC, arm64 translated (`--arch aarch64`) | ~83 s | 38 s |

Translated arm64 runs on the PC through `ndk_translation` (89 % of samples in its code
cache). It is slower and, running on x86 memory ordering, no stand-in for arm64.
