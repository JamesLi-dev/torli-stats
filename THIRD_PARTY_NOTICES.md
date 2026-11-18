# Third-party notices

## RunCatNeo runner artwork

`Resources/runner-*.png` contains the running animations used by the Torli
Stats status-bar logo: RunCat, Beagle, Chicken, Dinosaur, Fishman, Frog, Horse,
Rabbit, Rubber Duck, Classic Cat, Golden Retriever, Wall Breaker, and Dojo Panda.

- Artwork copyright: Copyright 2026 Kyome22 (Takuto Nakamura), IshankChoudhary,
  and 总钻风 (custsly)
- Source projects: [RunCatNeo](https://github.com/runcat-dev/RunCatNeo) and
  [RunnerGallery](https://github.com/runcat-dev/RunnerGallery)
- License: Apache License, Version 2.0
- License text: [`LICENSES/Apache-2.0.txt`](LICENSES/Apache-2.0.txt)
- RunnerGallery metadata attribution:
  - Classic Cat and Golden Retriever: Takuto Nakamura (Kyome22)
  - Wall Breaker: 总钻风 (custsly)
  - Dojo Panda: IshankChoudhary

Monochrome sprite sheets are rendered as macOS menu-bar template images; the
color Wall Breaker and Dojo Panda sheets preserve their original colors. The
sprite sheets are otherwise unmodified.

## Notes and edge-deck implementation

Torli Stats embeds and adapts an MIT-licensed notes, edge-deck, editing,
archive, import/export, keyboard-shortcut, and localization implementation.

- Copyright: Copyright 2026 Aymen Hamza
- License: MIT License
- License text: [`LICENSES/Notes-Engine-MIT.txt`](LICENSES/Notes-Engine-MIT.txt)

## Zstandard decompressor

The app includes the Zstandard 1.5.7 streaming decompressor from
https://github.com/facebook/zstd/tree/v1.5.7 under its BSD license.
Copyright (c) Meta Platforms, Inc. and affiliates. All rights reserved.

The source in `Sources/CZstd/zstddeclib.c` was generated from the upstream
`build/single_file_libs/zstddeclib-in.c` with `combine.py -r ../../lib -x legacy/zstd_legacy.h -o zstddeclib.c zstddeclib-in.c`.
The public headers are copied from upstream `lib/zstd.h` and `lib/zstd_errors.h`.
The license is included in `LICENSES/Zstandard-BSD.txt`.
