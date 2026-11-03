# vrxr

Native **full-FOV side-by-side (SBS) 3D streaming** to standalone VR headsets — **Pico 4** and **Quest 3** — and to a **phone-in-viewer VR client**, with **no VorpX, no UEVR, no SteamVR**.

Any flat game or desktop is turned into a side-by-side 3D frame by a **lightweight luminance-based depth shader**, encoded as HEVC, and streamed over the LAN. A native OpenXR app on the headset decodes it and paints it head-locked, filling your field of view with a correct per-eye stereo split — a "direct VR" experience, built from scratch. The same stream also drives a lightweight phone VR client for a Cardboard-style viewer.

Because the 3D is a cheap real-time shader (not a depth-estimation model), the whole capture → shade → encode → stream → decode path stays inside a real-time latency budget — good enough to **play GeForce Now and PS5 (Chiaki) in VR**.

### Two ways to make the stream

* **PC source** — a Windows PC runs the ReShade SBS shader over any game and streams it (needs an NVIDIA GPU for `hevc_nvenc`).
* **ShieldCast** — an **Android** app that captures its *own* screen, runs the 2D→3D depth shader on-device, encodes, and streams. **No PC at all.** It runs on Android TV / Nvidia Shield **and on Android phones and tablets** — any reasonably capable Android device can be the whole source. On more capable phones/tablets you can even run PC games *locally* through an emulator like **DroidDeck / GameNative / Winlator** and capture those — fully **PC-free *and* cloud-free**.

### Clients

* **`vrxr`** — native OpenXR app for Pico 4 / Quest 3 (this repo's main app).
* **`vrstream`** — phone VR client (tested on Galaxy Note 10+) for a phone-in-headset viewer.

Both clients take the same HEVC SBS stream on UDP :5000, from either source, with the same decode pipeline.

---

## How it works

```
SOURCE (PC or Android)                       CLIENT (headset / phone)
────────────────────────────────            ─────────────────────────────────────────
flat game / desktop                               UDP :5000
  │  2D→3D luminance depth shader              │  NalReceiver   (RFC 7798 HEVC depacketizer)
  ▼  → side-by-side frame                      ▼  H264Decoder   (HW HEVC → linear YUV_420_888, Image mode)
  ▼  HEVC encode (CBR, low-latency)            ▼  Stream        (triple-buffered Y / CbCr plane bridge → JNI)
  ▼  RTP ───────────────────────────────────▶ ▼  native-lib    (OpenXR + GLES3: YUV→RGB, SBS split,
                                                   head-locked quad layers)
```

* The frame arrives **already SBS-packed** (left-eye view in the left half, right-eye in the right) — that packing is done at the source, not in the headset.
* The client decodes in hardware to **linear YUV**, converts YUV→RGB on the GPU, and samples the correct half of the frame per eye.
* Output is two **head-locked OpenXR quad layers** (one per eye), so the image fills your FOV and rides with your view — flat and upright. vrxr **auto-detects the stream's aspect ratio** per frame, so 16:9, 21:9 ultrawide, or anything else displays with correct geometry (no stretch).

---

## Field of view — fixing the "zoomed in" look

A flat game renders at its own field of view (~70–90°). Shown head-locked and filling a headset's ~100°+ FOV, that reads as **zoomed in / magnified** — you're stretching a narrow-FOV image across a wide physical FOV. Nothing in the headset can add FOV the source never rendered, so the fix has to happen **at the source**. Two levers, best used together:

### 1. Force a 21:9 ultrawide aspect — *critical*

Most games are **Hor+**: a wider aspect ratio gives a wider *horizontal* FOV. On Android, use **Second Screen (by farmerbb)** to override the display size to 21:9 (e.g. **2560×1080**):

```
wm size 2560x1080      # what Second Screen applies under the hood (needs WRITE_SECURE_SETTINGS via ADB, no root)
```

This changes the **actual UI framebuffer** to 21:9, so Hor+ games render wider *and* ShieldCast captures the real wide frame. vrxr auto-detects the aspect and shows it correctly.

> ⚠️ **Use Second Screen / `wm size` — not the device's display-resolution menu.** The resolution menu changes the HDMI *output* mode, but the UI framebuffer that `MediaProjection` captures stays 16:9, so the wider FOV never reaches ShieldCast. Only the `wm size` override changes the framebuffer that gets captured. (If vrxr still looks 16:9 after switching resolutions, this is almost always why.)

Source support varies:

* **GeForce Now** — honors the 21:9 aspect ✅
* **Amazon Luna** — does **not** (stays 16:9) ❌
* **Local emulators (DroidDeck / GameNative / Winlator)** — works for Hor+ games; you can also set the game's own resolution/config to ultrawide for the same effect.
* Other sources — mileage varies; try it.

### 2. In-game FOV slider → max (fallback / stacking)

If the game exposes an FOV slider, set it to **max**. It **stacks** with the 21:9 aspect for the widest result, and it's your only lever in the rare game that ignores aspect ratio. For games with **no** FOV slider — most indie horror — the 21:9 aspect change is the only option, which is why it's the primary fix. For Unreal/Unity games with a hidden FOV, a config edit or engine console can sometimes force it (check PCGamingWiki per game).

> Expect flat-in-VR content to look **larger / closer** than it does on a monitor — that's the virtual-screen magnification of the medium, not a distortion. Quick sanity check: anything that should be round (a wheel, a planet, a HUD reticle) should look **circular**, not an oval. Circular = aspect is correct.

---

## PC source

**1. Generate the SBS image.** Run the ReShade depth shader (`sbsluma.fx`) so any game becomes a side-by-side 3D frame.

* `Depth Strength` — amount of 3D; ~3 is a good start.

**2. Capture + stream.** `vrhevc.bat` launches OBS (Display Capture → Virtual Camera) and pipes it through ffmpeg:

```bat
REM set bitrate / headset IP inside
```

* Set resolution/frame rate inside OBS. The client auto-detects the frame size, so you can run anything up to ~4K as your encoder and network allow.
* Requires an NVIDIA GPU for `hevc_nvenc` (tested on an RTX 5060 Ti).

---

## ShieldCast source (Android — no PC)

`ShieldCast` is an Android app (`com.pearce.shieldcast`) that makes the Android device itself the whole streaming source — it captures the full screen, applies the 2D→3D depth shader on the GPU, HEVC-encodes it, and streams RTP to the same vrxr / vrstream clients. It runs on Android TV / Nvidia Shield, and on Android phones and tablets.

```
Android device (TV box / phone / tablet)
──────────────────────────────────────────────
whole screen
  │  MediaProjection → VirtualDisplay
  ▼  GL: 2D→3D luminance-depth shader, SBS pack
  ▼  MediaCodec HEVC (CBR + low-latency, intra-refresh, no B-frames)
  ▼  RtpSender  (RFC 7798 packetizer, the inverse of NalReceiver)
  └── UDP :5000 ──▶  vrxr headset  /  vrstream phone
```

**Use:** launch ShieldCast, enter the headset/phone IP, set depth / resolution / bitrate / frame-rate / 3D mode, press **Start**, accept the screen-capture prompt. Then open vrxr (headset) or vrstream (phone).

**Settings** (all saved between launches):

* **3D depth strength** — live-adjustable even while streaming.
* **3D mode** — Sink-in (default) or Pop (out of the screen).
* **Resolution** — 540 / 720 / 810 / 1080 / 1440p per eye (width auto-scales to the screen aspect, so it follows your 16:9 / 21:9 setting).
* **Bitrate** — 4–40 Mbit.
* **Frame rate** — 30 / 60 fps.

**Virtual-screen toggle from a TV remote:** double-press **Back** to flip between FULL FOV and the FIT / virtual screen — the same toggle the PC gamepad sends. Requires enabling ShieldCast once under **Settings → Accessibility** (Android disables it on every reinstall, so re-enable after each new build).

**What runs as the source:**

* **Cloud gaming** (GeForce Now, etc.) — captures fine; pair with the 21:9 trick above for wide FOV.
* **Local PC-game emulators** on capable phones/tablets — DroidDeck / GameNative / Winlator run Windows games on-device; ShieldCast captures them, so you get 3D VR with **no PC and no cloud**. The heavier the device the better (translation layers are CPU-hungry); the emulated game's own frame pacing is the main thing that affects smoothness.
* **DRM-protected video captures black** (Netflix, etc.) — Android blocks secure surfaces from screen capture. Games, apps, UI, and non-DRM video capture fine.

**Device notes:**

* **Encoder width is the real ceiling.** SBS doubles the width, so (per-eye height × aspect × 2) must fit the device's HW encoder limit. On the Shield's Tegra X1 that's ~4K wide (≈1080p/eye at 16:9); a Snapdragon 8-Gen-class phone/tablet encoder goes higher. At 21:9 the frame is wider for a given height, so drop a resolution step if the encoder won't start.
* Tune down for a phone client, up for a headset — the Pico 4 / Quest 3 (Snapdragon XR2) decoders handle 1080p / 60 fps / 20+ Mbit easily; the phone client is happiest around 810p / 12 Mbit / 30 fps.

---

## Headset app (vrxr)

Native OpenXR app (`com.pearce.vrxr`), vendor-neutral so one APK runs on both Pico 4 and Quest 3.

|File|Role|
|-|-|
|`NalReceiver.java`|RTP HEVC depacketizer (RFC 7798: single NAL / AP / FU)|
|`H264Decoder.java`|HEVC MediaCodec decoder, Image mode → linear YUV_420_888|
|`Stream.java`|Triple-buffered Y / CbCr plane bridge to native|
|`native-lib.cpp`|OpenXR session + GLES3 render: YUV→RGB, per-eye SBS split, auto-aspect head-locked quad layers|

### Headset controls (right thumbstick)

* **Right-stick X — convergence.** Live-shifts the stereo separation to tune depth/comfort.
* **Right-stick Y — FULL-mode zoom.** Push up to pull the screen back (see more / less magnified), down to bring it closer. FULL mode is sized to fill the FOV with the whole screen visible by default; this fine-tunes it per headset and per game.
* **L3 + R3 (or TV-remote double-Back) — FULL / FIT toggle.** See Gamepad control below.

### Run

1. Sideload the APK.
2. Start a source (`vrhevc.bat` on the PC, or ShieldCast on the Android device).
3. Launch **vrxr** on the headset.

---

## Phone version (vrstream)

A lightweight Android phone client for a **phone-in-viewer** (Cardboard-style) headset — the same toolchain without a standalone headset.

* Takes the **same HEVC SBS stream** from either source, on the same UDP port.
* Reuses the proven **RTP depacketizer + HEVC MediaCodec** pipeline (`NalReceiver` / `H264Decoder`).
* Renders the SBS frame as a **stereo VR view with lens (barrel) distortion**, so each eye looks through the phone's lenses in a viewer mount.
* **Self-healing decode:** a watchdog detects if the picture stops updating and automatically recovers (rebuild decode surface → full view rebuild → process restart as needed), so a transient stall becomes a brief blip instead of a frozen stream you have to restart by hand.
* Tested on a **Samsung Galaxy Note 10+**.

---

## Gamepad control (vrxrctl)

`vrxrctl.exe` is a tiny, dependency-free Windows helper that `vrhevc.bat` launches alongside OBS and ffmpeg. It reads your gamepad and sends a small UDP control signal to the headset and phone — so your PC controller can drive the view while you're in VR.

**L3 + R3 (click both thumbsticks at once) toggles the screen mode:**

* **Full FOV** — the picture fills your whole view (default, most immersive).
* **Fit / virtual screen** — the picture pulls back into a framed panel so you can see the *entire* screen at once: all four edges, menus, minimaps, chat, anything tucked in the corners. Tap to pop out and read whatever you need, tap again to snap right back to full FOV.

Works the same on Pico, Quest and the phone, and stays in sync across them. When the source is ShieldCast, **double-press Back on the TV remote** does the same toggle (no PC gamepad needed).

**Targeting — the `PHONE_IP` line:**

`vrxrctl` auto-broadcasts across your LAN, so **the headset needs no setup** — leave the IP blank. The **phone needs its IP** (it only accepts unicast), so set it in the bat:

```bat
REM Phone toggle: put your phone's LAN IP here. Leave blank if you only use a headset.
set PHONE_IP=
start "" "%~dp0vrxrctl.exe" %PHONE_IP%
```

Blank `PHONE_IP` = broadcast only (headset works, phone inactive). Set it (e.g. `set PHONE_IP=192.168.0.50`) and the phone gets the toggle too.

---

## Notes & limitations

* **8-bit SDR only.** HDR / 10-bit streams aren't handled by the decode path.
* **Hardware HEVC decode.** Uses Image mode (linear YUV) specifically to avoid Qualcomm UBWC buffers, which render black when sampled as an external texture on some runtimes (notably Pico 4).
* **Head-locked, display-only.** The image fills your FOV and follows your head; it does **not** feed head tracking back into the game (no in-game head-look yet).
* **Monocular (fake) 3D.** Depth is inferred from luminance by a lightweight shader — convincing and nearly free to run, but not true stereo. That's the trade that keeps it inside a real-time latency budget where a depth-AI model would not.
* **FOV comes from the source, not the headset.** A flat capture only contains the game's own FOV; widen it at the source (21:9 aspect and/or in-game FOV) — see the Field of view section.
* Source must be genuinely SBS. A flat (non-shader) feed will show as a 2D image with a seam down the middle — that's the per-eye split working on non-stereo input, not a bug.

---

## Roadmap

* [ ] Optional head-pose feedback to the source for in-game head-look

---

## License

MIT
