# iPhone Mirroring 15

A small native macOS viewer for TrollVNC, aimed at jailbroken iPhones including iOS 15.

## Build

Requires Xcode Command Line Tools, GStreamer development libraries and plugins (`gstreamer`, `gstreamer-app`, `gstreamer-video`, `gio`, RTP, and libav), and UxPlay. Run:

```sh
make app
open build/iPhoneMirroring15.app
```

The Makefile uses `pkg-config` to find GStreamer. UxPlay defaults to `../UxPlay/build/uxplay` beside this repository; set `UXPLAY_PATH` to override it when launching the executable directly:

```sh
UXPLAY_PATH=/path/to/uxplay ./build/iPhoneMirroring15.app/Contents/MacOS/iPhoneMirroring15
```

On launch, the app starts UxPlay as an AirPlay receiver. On the iPhone, open Control Center and select **iPhone Mirroring 15** under Screen Mirroring. The app receives the video over local RTP and decodes it with GStreamer `avdec_h264`.

The app discovers `_rfb._tcp` TrollVNC devices or accepts a host and port manually. TrollVNC's default port is `5901`; the last VNC target reconnects on later launches. Allow local network access when macOS asks.

The main app surface is a portrait, borderless device display. Use **Connection → Connect to iPhone…** or **⌘K** to choose a nearby device or enter an address. Discovery does not infer Wi-Fi state from macOS interface APIs.

## Controls

- Click and drag: touch the AirPlay screen through TrollVNC
- Right click: Home
- Middle click: Power
- Home and Power buttons are also available in the toolbar

Optional VNC passwords are saved in Keychain after a successful connection.

## Compatibility

The client negotiates RFB 3.8 and classic VNC password authentication to get screen dimensions and send input. It does not request or render VNC framebuffer updates; AirPlay supplies the displayed video. This experiment expects H.264 AirPlay mirroring. VNC authentication does not encrypt control traffic; use it only on a trusted LAN or tunnel.
