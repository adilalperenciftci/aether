- **CI reports lavapipe's D32S8 crash from a draw in plain C.**
  `.github/scripts/lavapipe_d32s8_draw.c` draws a quad into a
  `D32_SFLOAT_S8_UINT` depth-stencil attachment with no Aether code, and
  the Ubuntu 24.04 lavapipe job and the Windows contrib leg run it 20 times
  in that format and 20 in `D24_UNORM_S8_UINT`, reporting how many runs
  crashed in each without failing on them. Mesa 26.1.8's llvmpipe dies in
  about half the D32S8 runs where it runs 8 lanes wide: an aligned 32-byte
  load from depth storage that is only 16-byte aligned. D24S8 and 4-lane
  llvmpipe never crash. The counts say when a Mesa release fixes it
  (#2410).
