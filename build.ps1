rm ./qswagger-linux-x64 2>$null
rm ./qswagger.exe 2>$null
echo "Building for Windows.."
odin build qswagger -o:speed
echo "Building for Linux.."
wsl -- ~/Odin/odin build qswagger "-out:qswagger-linux-x64" "-o:speed"
