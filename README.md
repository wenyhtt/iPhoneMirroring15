# iPhone Mirroring 15

A small native macOS viewer for TrollVNC, aimed at jailbroken iPhones including iOS 15.

## Build

Requires Xcode Command Line Tools, GStreamer development libraries and plugins (`gstreamer`, `gstreamer-app`, `gstreamer-video`, `gio`, `level`, UDP, RTP, and libav), and a built UxPlay checkout at `../UxPlay`. Run:

```sh
make app
open build/iPhoneMirroring15.app
```

`make app` copies UxPlay, the required GStreamer plugins and their dynamic-library dependencies, and GStreamer’s plugin scanner into the app bundle. The built app uses those bundled files; the build machine still needs the development packages. The build sets the app’s minimum macOS version from the bundled GStreamer runtime. This machine’s MacPorts GStreamer requires macOS 26; use a runtime built for an older macOS to build a compatible app for older systems. Set `UXPLAY_PATH` to select a different UxPlay binary at build time or when launching the executable directly:

```sh
make app UXPLAY_PATH=/path/to/uxplay
UXPLAY_PATH=/path/to/uxplay ./build/iPhoneMirroring15.app/Contents/MacOS/iPhoneMirroring15
```

The app bundle includes UxPlay’s GPLv3 license in `Contents/Resources/ThirdPartyLicenses`. Before redistribution, provide the corresponding source and license notices required by UxPlay and the bundled GStreamer/FFmpeg components. The bundled native libraries match the build machine’s architecture.

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
