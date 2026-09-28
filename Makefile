.PHONY: app run test icon dmg install clean

app:            ## Build build/Nod.app (universal, ad-hoc signed)
	scripts/build-app.sh

run: app        ## Build and launch
	open build/Nod.app

test:           ## Run the unit tests
	swift test

icon:           ## Re-render Support/AppIcon.icns from the NodMark view
	swift build
	rm -rf build/Nod.iconset
	.build/debug/Nod --render-icon build/Nod.iconset
	iconutil -c icns build/Nod.iconset -o Support/AppIcon.icns

dmg: app        ## Package build/Nod.dmg, with an Applications shortcut to drag onto
	rm -rf build/dmg build/Nod.dmg
	mkdir -p build/dmg
	cp -R build/Nod.app build/dmg/
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname Nod -srcfolder build/dmg -ov -format UDZO build/Nod.dmg
	rm -rf build/dmg

install: app    ## Copy to /Applications
	rm -rf /Applications/Nod.app
	cp -R build/Nod.app /Applications/

clean:
	rm -rf .build build
