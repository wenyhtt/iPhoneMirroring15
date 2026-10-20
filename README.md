# iPhone Mirroring 15

A small native macOS viewer for TrollVNC, aimed at jailbroken iPhones including iOS 15.

## Build

Requires Xcode Command Line Tools and macOS 14 or newer. Run:

```sh
make app
open build/iPhoneMirroring15.app
```

The app discovers `_rfb._tcp` devices on the local network or accepts a host and port manually. TrollVNC's default port is `5901`. On first launch, macOS asks to allow local network discovery.

The main app surface is a portrait, borderless device display. Use **Connection → Connect to iPhone…** or **⌘K** to choose a nearby device or enter an address. Discovery does not infer Wi-Fi state from macOS interface APIs.

## Controls

- Click and drag: touch the phone screen
- Right click: Home
- Middle click: Power
- Home and Power buttons are also available in the toolbar

Optional VNC passwords are saved in Keychain after a successful connection.

## Compatibility

The client negotiates RFB 3.8, classic VNC password authentication, Raw framebuffer updates, and DesktopSize updates. It intentionally does not include LibVNCClient or Apple binaries. Servers that require compressed framebuffer encodings or other authentication types are not supported. VNC authentication does not encrypt the screen stream; use it only on a trusted LAN or tunnel.
