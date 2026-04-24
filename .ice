BUILD_RELEASE :: "odin build src -vet -o:speed"

run:
  odin run src -- $$ARGS
release:
  $$BUILD_RELEASE -out:qswagger.exe
  wsl sh -c "$$BUILD_RELEASE -out:qswagger-linux-x64"
