.PHONY: app clean

app:
	mkdir -p build/iPhoneMirroring15.app/Contents/MacOS
	swiftc -parse-as-library -module-cache-path build/ModuleCache -sdk "$(shell xcrun --sdk macosx --show-sdk-path)" -target "$(shell uname -m)-apple-macosx14.0" Sources/iPhoneMirroring15/*.swift -framework AppKit -framework Network -framework Security -framework CoreGraphics -framework CoreFoundation -o build/iPhoneMirroring15.app/Contents/MacOS/iPhoneMirroring15
	cp Info.plist build/iPhoneMirroring15.app/Contents/Info.plist
	printf 'APPL????' > build/iPhoneMirroring15.app/Contents/PkgInfo
	codesign --force --deep --sign - build/iPhoneMirroring15.app

clean:
	rm -rf .build build
