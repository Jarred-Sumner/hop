VERSION = v0.0.0

build-linux:
	zig build -Drelease-fast -Dtarget=x86_64-linux-gnu
	rm -rf /tmp/hop-linux-x64/
	mkdir -p /tmp/hop-linux-x64/
	cp zig-out/bin/hop /tmp/hop-linux-x64/hop
	cd /tmp && rm -rf hop-linux-x64.tar.gz; tar -czvf hop-linux-x64.tar.gz hop-linux-x64;
	cd /tmp && rm -rf hop-linux-x64.zip; zip -r hop-linux-x64.zip hop-linux-x64;
	gh release upload $(VERSION) /tmp/hop-linux-x64.tar.gz --clobber
	gh release upload $(VERSION) /tmp/hop-linux-x64.zip --clobber

build-mac-x64:
	zig build -Drelease-fast -Dtarget=x86_64-macos-gnu
	rm -rf /tmp/hop-macos-x64/
	mkdir -p /tmp/hop-macos-x64/
	cp zig-out/bin/hop /tmp/hop-macos-x64/hop
	cd /tmp && rm -rf hop-macos-x64.tar.gz; tar -czvf hop-macos-x64.tar.gz hop-macos-x64;
	cd /tmp && rm -rf hop-macos-x64.zip; zip -r hop-macos-x64.zip hop-macos-x64;
	gh release upload $(VERSION) /tmp/hop-macos-x64.tar.gz --clobber
	gh release upload $(VERSION) /tmp/hop-macos-x64.zip --clobber

compile-mac-arch64:
	zig build -Drelease-fast -Dtarget=aarch64-macos-gnu

build-mac-arch64:
	zig build -Drelease-fast -Dtarget=aarch64-macos-gnu
	rm -rf /tmp/hop-macos-apple-silicon/
	mkdir -p /tmp/hop-macos-apple-silicon/
	cp zig-out/bin/hop /tmp/hop-macos-apple-silicon/hop
	cd /tmp && rm -rf hop-macos-apple-silicon.tar.gz; tar -czvf hop-macos-apple-silicon.tar.gz hop-macos-apple-silicon;
	cd /tmp && rm -rf hop-macos-apple-silicon.zip; zip -r hop-macos-apple-silicon.zip hop-macos-apple-silicon;
	gh release upload $(VERSION) /tmp/hop-macos-apple-silicon.tar.gz --clobber
	gh release upload $(VERSION) /tmp/hop-macos-apple-silicon.zip --clobber

upload-hop-files:
	cd /tmp && hop ./hop-linux-x64 && hop hop-macos-x64 && hop hop-macos-apple-silicon
	gh release upload $(VERSION) /tmp/hop-linux-x64.hop --clobber
	gh release upload $(VERSION) /tmp/hop-macos-x64.hop --clobber
	gh release upload $(VERSION) /tmp/hop-macos-apple-silicon.hop --clobber