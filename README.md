# qswagger
Typescript request generator for swagger

## installation
Download `qswagger.exe` from https://github.com/Patrolin/qswagger/releases

## usage
Generate apis and models
```
./qswagger.exe <urlOrFile>.json
```

Generate apis and models from multiple modules
```
./qswagger.exe <urlOrFile1>.json <urlOrFile2>.json
```

Generate apis and models \
with `{dateFrom: Date}` and `dateFrom: params.dateFrom.toISOString()` \
instead of `{dateFrom: string}` and `dateFrom: String(params.dateFrom)`
```
./qswagger.exe <urlOrFile>.json -gen_dates
```

Generate apis and models \
with `{dateFrom: Date}` and `dateFrom: <date_fmt>` \
instead of `{dateFrom: string}` and `dateFrom: String(params.dateFrom)` \
(`Utils` must be imported manually)
```
./qswagger.exe <urlOrFile>.json -gen_dates -date_fmt "Utils.printIsoDate(%v)"
```

## dev
- **Windows** \
  - **Install Odin**
    - Install Odin from https://odin-lang.org/ \
  - **Build qswagger**
    ```
    odin build qswagger
    ```
- **Ubuntu 24.xx**
  - **Install Odin** \
    (copy paste from https://odin-lang.org/docs/install/#others-unix)
    ```
    sudo apt update
    sudo apt upgrade
    sudo apt install clang llvm make libssl-dev
    cd ~  # wherever you want to install it
    git clone https://github.com/odin-lang/Odin
    cd Odin
    git checkout dev-2025-04  # whatever version you want
    make release-native
    ```
  - **Build qswagger**
    ```
    odin build qswagger -out:qswagger-linux-x64
    ```
