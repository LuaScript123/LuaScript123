.PHONY: setup check map build serve studio-test package
setup:
	bash tools/bootstrap.sh
check:
	bash tools/check.sh
map:
	python3 tools/export-map.py
	python3 tools/export-world.py
build: map
	mkdir -p build
	.tools/bin/rojo build default.project.json --output build/FerEtFioles.rbxlx
serve: map
	.tools/bin/rojo serve default.project.json
studio-test:
	mkdir -p build
	.tools/bin/rojo build test.project.json --output build/StudioSmoke.rbxlx
package: build studio-test
	python3 tools/package.py
