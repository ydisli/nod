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

dmg: app        ## Package build/Nod.dmg
	rm -f build/Nod.dmg
	hdiutil create -volname Nod -srcfolder build/Nod.app -ov -format UDZO build/Nod.dmg

install: app    ## Copy to /Applications
	rm -rf /Applications/Nod.app
	cp -R build/Nod.app /Applications/

clean:
	rm -rf .build build
