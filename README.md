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
