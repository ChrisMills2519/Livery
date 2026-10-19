# Texture credits

All ground textures are 1K JPEG diffuse + OpenGL normal maps downloaded from
[Poly Haven](https://polyhaven.com) and released under
[CC0](https://creativecommons.org/publicdomain/zero/1.0/). Attribution is not
required, but is recorded here.

| Local files | Poly Haven asset | Author | Source |
| --- | --- | --- | --- |
| `ground/grass_albedo.jpg`, `ground/grass_normal.jpg` | Aerial Grass Rock | Rob Tuytel | https://polyhaven.com/a/aerial_grass_rock |
| `ground/dirt_albedo.jpg`, `ground/dirt_normal.jpg` | Dirt Floor | eye-candy.xyz | https://polyhaven.com/a/dirt_floor |
| `ground/path_albedo.jpg`, `ground/path_normal.jpg` | Aerial Ground Rock | Rob Tuytel | https://polyhaven.com/a/aerial_ground_rock |
| `ground/sand_albedo.jpg`, `ground/sand_normal.jpg` | Sand 01 | Rob Tuytel | https://polyhaven.com/a/sand_01 |

Download URLs follow the Poly Haven file API layout:

```
https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/<asset>/<asset>_diff_1k.jpg
https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/<asset>/<asset>_nor_gl_1k.jpg
```

Import note: all files are kept lossless (`compress/mode=0`) with
`detect_3d/compress_to=0`, matching the project-wide rule in `agents.md`
(VRAM-compressed textures crash the GL Compatibility setup on the dev machine).
