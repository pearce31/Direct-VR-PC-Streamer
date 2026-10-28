# vrxr

Native **full-FOV side-by-side (SBS) 3D streaming** to standalone VR headsets — **Pico 4** and **Quest 3** — and to a **phone-in-viewer VR client**, with **no VorpX, no UEVR, no SteamVR**.

A PC captures any flat game or desktop, runs a ReShade SBS depth shader over it, and streams it as HEVC. A native OpenXR app on the headset decodes the stream and paints it head-locked, filling your field of view, with a correct per-eye stereo split — "direct VR" experience, built from scratch. The same stream also drives a lightweight phone VR client for a Cardboard-style viewer.

Two clients share one PC streamer and the same decode pipeline:

* **`vrxr`** — native OpenXR app for Pico 4 / Quest 3 (this repo's main app).
* **`vrstream`** — phone VR client (tested on Galaxy Note 10+) for a phone-in-headset viewer.

---

## How it works

```
PC                                           Headset (Pico 4 / Quest 3)
────────────────────────────────            ─────────────────────────────────────────
game                                              UDP :5000
  │  ReShade SBS shader (sbsluma.fx)           │  NalReceiver   (RFC 7798 HEVC depacketizer)
  ▼  via  OBS (Display Capture →               ▼  H264Decoder   (HW HEVC → linear YUV_420_888, Image mode)
       Virtual Camera)                         ▼  Stream        (triple-buffered Y / CbCr plane bridge → JNI)
  │                                            ▼  native-lib    (OpenXR + GLES3: YUV→RGB, SBS split,
  ▼  ffmpeg hevc_nvenc → RTP ───────────────▶     head-locked quad layers)
```

* The frame arrives **already SBS-packed** (left-eye view in the left half, right-eye in the right) — that packing is done on the PC by the ReShade shader, not in the headset.
* The headset decodes in hardware to **linear YUV**, converts YUV→RGB on the GPU, and samples the correct half of the frame per eye.
* Output is two **head-locked OpenXR quad layers** (one per eye), so the image fills your FOV and rides with your view — flat and upright.

---

## PC side

* Set Resolution/frame rate inside OBS

**1. Generate the SBS image.** Run the ReShade depth shader (`sbsluma.fx`) so any game becomes a side-by-side 3D frame.

* `Depth Strength` — amount of 3D 3 is recommended.

**2. Capture + stream.** `vrhevc.bat` launches OBS (Display Capture → Virtual Camera) and pipes it through ffmpeg:

```bat
set bitrate/headset IP inside
```

* Resolution/bitrate are yours to choose — the headset auto-detects the frame size, so you can run anything up to ~4K as your encoder and network allow.
* Requires an NVIDIA GPU for `hevc_nvenc` (tested on an RTX 5060 Ti).

---

## Headset app

Native OpenXR app (`com.pearce.vrxr`), vendor-neutral so one APK runs on both Pico 4 and Quest 3.

|File|Role|
|-|-|
|`NalReceiver.java`|RTP HEVC depacketizer (RFC 7798: single NAL / AP / FU)|
|`H264Decoder.java`|HEVC MediaCodec decoder, Image mode → linear YUV_420_888|
|`Stream.java`|Triple-buffered Y / CbCr plane bridge to native|
|`native-lib.cpp`|OpenXR session + GLES3 render: YUV→RGB, per-eye SBS split, head-locked quad layers|

### Run

1. Sideload the APK.
2. Start `vrhevc.bat` to start the stream.
3. Launch **vrxr** on the headset.

---

## Phone version (vrstream)

A lightweight Android phone client for a **phone-in-viewer** (Cardboard-style) headset — the same toolchain without a standalone headset.

* Takes the **same HEVC SBS stream** from the same PC streamer (`vrhevc.bat`), on the same UDP port.
* Reuses the proven **RTP depacketizer + HEVC MediaCodec** pipeline (`NalReceiver` / `H264Decoder`).
* Renders the SBS frame as a **stereo VR view with lens (barrel) distortion**, so each eye looks through the phone's lenses in a viewer mount.
* Tested on a **Samsung Galaxy Note 10+** (strong hardware HEVC decoder — comfortably handles 4K60).

Same requirements and streaming notes as above.

---

## Gamepad control (vrxrctl)

`vrxrctl.exe` is a tiny, dependency-free Windows helper that `vrhevc.bat` launches alongside OBS and ffmpeg. It reads your gamepad and sends a small UDP control signal to the headset and phone — so your PC controller can drive the view while you're in VR.

**L3 + R3 (click both thumbsticks at once) toggles the screen mode:**

* **Full FOV** — the picture fills your whole view (default, most immersive).
* **Fit / virtual screen** — the picture pulls back into a framed panel so you can see the *entire* screen at once: all four edges, menus, minimaps, chat, anything tucked in the corners. Tap L3+R3 to pop out and read whatever you need, tap again to snap right back to full FOV.

Works the same on Pico, Quest and the phone, and stays in sync across them.

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
* **Head-locked, display-only.** The image fills your FOV and follows your head; it does **not** feed head tracking back into the PC game (no in-game head-look yet).
* Source must be genuinely SBS. A flat (non-shader) desktop will show as a 2D image with a seam down the middle — that's the per-eye split working on non-stereo input, not a bug.

---

## Roadmap

* [ ] Optional head-pose feedback to the PC for in-game head-look

---

## License

MIT
