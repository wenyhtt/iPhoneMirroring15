.PHONY: app clean

GST_CFLAGS := $(shell pkg-config --cflags gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0)
GST_LIBDIR := $(shell pkg-config --variable=libdir gstreamer-1.0)
GST_LIBS := $(shell pkg-config --libs-only-L --libs-only-l gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0 gio-2.0)
GST_PLUGIN_DIR := $(shell pkg-config --variable=pluginsdir gstreamer-1.0)
GST_PLUGIN_SCANNER := $(shell pkg-config --variable=libexecdir gstreamer-1.0)/gstreamer-1.0/gst-plugin-scanner
MACOSX_DEPLOYMENT_TARGET ?= $(shell vtool -show-build "$(GST_LIBDIR)/libgstreamer-1.0.0.dylib" | awk '$$1 == "minos" { print $$2; found = 1; exit } END { if (!found) print "14.0" }')
UXPLAY_PATH ?= ../UxPlay/build/uxplay
UXPLAY_LICENSE ?= ../UxPlay/LICENSE

app:
	rm -rf build/iPhoneMirroring15.app
	mkdir -p build/iPhoneMirroring15.app/Contents/MacOS
	clang -std=c11 -target "$(shell uname -m)-apple-macosx$(MACOSX_DEPLOYMENT_TARGET)" -c Sources/iPhoneMirroring15/AirPlayVideo.c $(GST_CFLAGS) -o build/AirPlayVideo.o
	swiftc -parse-as-library -module-cache-path build/ModuleCache -sdk "$(shell xcrun --sdk macosx --show-sdk-path)" -target "$(shell uname -m)-apple-macosx$(MACOSX_DEPLOYMENT_TARGET)" -import-objc-header Sources/iPhoneMirroring15/AirPlayVideo.h Sources/iPhoneMirroring15/*.swift build/AirPlayVideo.o -framework AppKit -framework Network -framework Security -framework CoreGraphics -framework CoreFoundation $(GST_LIBS) -o build/iPhoneMirroring15.app/Contents/MacOS/iPhoneMirroring15
	cp Info.plist build/iPhoneMirroring15.app/Contents/Info.plist
	printf 'APPL????' > build/iPhoneMirroring15.app/Contents/PkgInfo
	python3 Scripts/bundle_runtime.py --app build/iPhoneMirroring15.app --uxplay "$(UXPLAY_PATH)" --plugin-dir "$(GST_PLUGIN_DIR)" --plugin-scanner "$(GST_PLUGIN_SCANNER)" --uxplay-license "$(UXPLAY_LICENSE)"
	codesign --force --deep --sign - build/iPhoneMirroring15.app

clean:
	rm -rf .build build
