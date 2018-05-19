#include <stdint.h>
#include "global.h"

#if 0
typedef struct VWFCanvas {
  uint32_t *data;
  unsigned short width, height;
} VWFCanvas;

/**
 * Fills a tilemap with a rectangle of tile numbers that ascend
 * in column-major order.
 * @param dst &(MAP[mapnum][y][x])
 * @param tilenum palette and tile number of tile
 * @param width width of text box in tiles
 * @param height height of text
 */
void loadMapColMajor(unsigned short *dst, unsigned int tilenum,
                     unsigned int width, unsigned int height) {
  for (unsigned int rows_left = height;
       rows_left > 0;
       --rows_left) {
    unsigned short *rowptr = dst;
    unsigned int rowtilenum = tilenum;
    for (unsigned int cols_left = width;
         cols_left >= 0;
         --cols_left) {
      *dst++ = rowtilenum;
      rowtilenum += height;
    }
    tilenum += 1;
    dst += 32;
  }
}
#endif


/**
 * Fills a tilemap with a rectangle of tile numbers that ascend
 * in row-major order.
 * @param dst &(BG[mapnum][y][x])
 * @param tilenum palette and tile number of tile
 * @param width width of text box in tiles
 * @param height height of text
 */
void loadMapRowMajor(unsigned short *dst, unsigned int tilenum,
                     unsigned int width, unsigned int height) {
  for (; height > 0; --height) {
    unsigned short *rowptr = dst;
    for (unsigned int cols_left = width;
         cols_left > 0;
         --cols_left) {
      *rowptr++ = tilenum++;
    }
    dst += 32;
  }
}

extern const unsigned char vwfChrData[][8];
extern const unsigned char vwfChrWidths[];
/*
 = {
  {0, 0, 0, 0, 0, 0, 0, 0},
  {0x00, 0x01, 0x01, 0x01, 0x01, 0x00, 0x01},
  {0x00, 0x05, 0x05},
  {0x00, 0x0A, 0x1F, 0x0A, 0x1F, 0x0A},
};

const unsigned char vwfGlyphWidths[] = {
  3, 2, 4, 6
};
*/

void vwf8PutTile(uint32_t *dst, unsigned int glyphnum,
                 unsigned int x, unsigned int color) {
  const unsigned char *glyph = vwfChrData[glyphnum - 32];
  unsigned int startmask = 0x0F << ((x & 0x07) * 4);
  dst += (x >> 3) << 3;
  color = (color & 0x0F) * 0x11111111;
  
  for (unsigned int htleft = 8; htleft > 0; --htleft) {
    unsigned int mask = startmask;
    unsigned int glyphdata = *glyph++;
    uint32_t *sliver = dst++;
    
    for(; glyphdata; glyphdata >>= 1) {
      if (glyphdata & 0x01) {
        uint32_t s = *sliver;
        *sliver = ((s ^ color) & mask) ^ s;
      }
      mask <<= 4;
      if (mask == 0) {
        mask = 0x0F;
        sliver += 8;
      }
    }
  }
}

const char *vwf8Puts(uint32_t *restrict dst, const char *restrict s,
                     unsigned int x, unsigned int color) {
  while (x < 240) {
    unsigned char c = *s & 0xFF;
    if (c < 32) return s;
    ++s;
    vwf8PutTile(dst, c, x, color);
    x += vwfChrWidths[c - 32];
  }
  return s;
}

unsigned int vwf8StrWidth(const char *s) {
  unsigned int x = 0;

  while (x < 240) {
    unsigned char c = *s & 0xFF;
    if (c < 32) return x;
    ++s;
    x += vwfChrWidths[c - 32];
  }
  return x;
}