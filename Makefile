.PHONY: app clean

GST_CFLAGS := $(shell pkg-config --cflags gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0)
GST_LIBS := $(shell pkg-config --libs-only-L --libs-only-l gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0 gio-2.0) -Xlinker -rpath -Xlinker $(shell pkg-config --variable=libdir gstreamer-1.0)

app:
	mkdir -p build/iPhoneMirroring15.app/Contents/MacOS
	clang -std=c11 -target "$(shell uname -m)-apple-macosx14.0" -c Sources/iPhoneMirroring15/AirPlayVideo.c $(GST_CFLAGS) -o build/AirPlayVideo.o
	swiftc -parse-as-library -module-cache-path build/ModuleCache -sdk "$(shell xcrun --sdk macosx --show-sdk-path)" -target "$(shell uname -m)-apple-macosx14.0" -import-objc-header Sources/iPhoneMirroring15/AirPlayVideo.h Sources/iPhoneMirroring15/*.swift build/AirPlayVideo.o -framework AppKit -framework Network -framework Security -framework CoreGraphics -framework CoreFoundation $(GST_LIBS) -o build/iPhoneMirroring15.app/Contents/MacOS/iPhoneMirroring15
	cp Info.plist build/iPhoneMirroring15.app/Contents/Info.plist
	printf 'APPL????' > build/iPhoneMirroring15.app/Contents/PkgInfo
	codesign --force --deep --sign - build/iPhoneMirroring15.app

clean:
	rm -rf .build build
