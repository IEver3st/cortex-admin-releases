# Third-party notices

Cortex-authored code is covered by [LICENSE](LICENSE). That license does not grant rights to third-party artwork, game assets, or trademarks.

Customer builds omit downloaded wheel, plate and clothing reference images unless a permission record in the development release inputs confirms redistribution of those exact bytes. Wheel and plate controls retain labels and live previews. Clothing falls back to drawable labels or the server's own captured catalog.

Development reference sources:

- Wheel reference screenshots: [GTA Wiki vehicle customization](https://gta.fandom.com/wiki/Vehicle_Customization_in_GTA_V/Wheels), downloaded by `tools/fetch-vehicle-catalog.py`. Per-image URLs and hashes remain in the development provenance records.
- Plate reference screenshots: [LCPDFR GTA Online license plates](https://www.lcpdfr.com/forums/topic/155615-gta-online-license-plates/), cropped from the sheet recorded by the same fetch tool.
- Clothing images and drawable identities: [Colbss/FiveM-ClothingData](https://github.com/Colbss/FiveM-ClothingData/tree/6178655616ea88e3e2bf191b32bc4878b9c3b5eb), pinned commit `6178655616ea88e3e2bf191b32bc4878b9c3b5eb`. Catalog identities are reference data; downloaded photographs are excluded without a separate permission record.
- Paint reference values: [DurtyFree gta-v-data-dumps](https://github.com/DurtyFree/gta-v-data-dumps). Source URLs and fetch hashes remain in the development catalog provenance.
- vMenu permission identifiers: [vMenu](https://github.com/TomGrobbe/vMenu/tree/f615b15b38df4e67742658e36a52a160dbcd88c6) public ACE names, pinned to commit `f615b15b38df4e67742658e36a52a160dbcd88c6`. Cortex implements its own permission checks; compatibility is limited as described in [README](README.md).

Cortex Admin loads the display font and presentation assets from the separately installed `cortex-lib`; they are not copied into these archives. The owners of third-party game assets and marks retain their rights. No endorsement is claimed.

## vMenu compatibility

vMenu mode is an independent Cortex implementation that recognises vMenu's public interface so existing servers keep their configuration: the ACE permission names and `vmenu_*` convar names and defaults listed in `shared/vmenu_reference.lua`, taken from [Tom Grobbe / vMenu](https://github.com/TomGrobbe/vMenu/tree/f615b15b38df4e67742658e36a52a160dbcd88c6). The menu tree, row names, menu titles, subtitles and row order mirror vMenu 3.8.67 so its users find each option where they expect it, and the menu behaviour was modelled on vMenu's menus. That structure is credited to vMenu. The Lua code is a Cortex implementation that runs on Cortex's own actions and permission checks; descriptions, help text and notifications are written for Cortex. No vMenu source files or assets are included. The weapon and weapon-component lists are game facts: each spawn name with the game's own text-label key, limited to weapons that have a vMenu weapon ACE.

Stock vehicle classes and paint palettes in `shared/vmenu_reference.lua`, the tattoo overlay catalog in `client/tattoo_catalog.lua`, and the ped models, player scenarios, damage packs and timecycle modifiers in `client/game_catalogs.lua` are generated from GTA V game data published in [DurtyFree/gta-v-data-dumps](https://github.com/DurtyFree/gta-v-data-dumps/tree/b65684e00f689fdec405c5f1055322c802d3c895). Chameleon paint names are read from the game at runtime.

vMenu is credited here as the menu this mode mirrors and is compatible with. Its license is reproduced for reference.

Upstream `LICENSE.md`, retained verbatim:

> Tom Grobbe - https://www.vespura.com/
>
> Copyright © 2017-2026
>
> You can use and edit this code to your liking as long as you don't ever claim it to be your own code and always provide proper credit.
> You're **not** allowed to sell vMenu or any code you take from it.
> If you want to release your own version of vMenu, you have to link the original GitHub repo, or release it via a Forked repo.

## Lucide 0.462.0 / Feather notices

ISC License

Copyright (c) for portions of Lucide are held by Cole Bemis 2013-2022 as part of Feather (MIT). All other copyright (c) for Lucide are held by Lucide Contributors 2022.

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.


## Svelte 5.57.1

Copyright (c) 2016-2025 [Svelte Contributors](https://github.com/sveltejs/svelte/graphs/contributors)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


## clsx 2.1.1

MIT License

Copyright (c) Luke Edwards <luke.edwards05@gmail.com> (lukeed.com)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


## Feather portions (MIT)

Copyright (c) 2013-2022 Cole Bemis

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
