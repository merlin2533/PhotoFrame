import { test } from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { processImage } from '../src/storage/thumbnails';

test('CMYK input is converted to sRGB for original and thumbnail', async () => {
  const cmyk = await sharp({
    create: { width: 64, height: 64, channels: 3, background: { r: 200, g: 120, b: 40 } },
  })
    .toColorspace('cmyk')
    .jpeg()
    .toBuffer();
  assert.equal((await sharp(cmyk).metadata()).space, 'cmyk');

  const out = await processImage(cmyk);
  assert.equal((await sharp(out.originalBuffer).metadata()).space, 'srgb');
  assert.equal((await sharp(out.thumbnailBuffer).metadata()).space, 'srgb');

  const { dominant } = await sharp(out.thumbnailBuffer).stats();
  assert.ok(Math.abs(dominant.r - 200) < 40, `r=${dominant.r}`);
  assert.ok(Math.abs(dominant.b - 40) < 40, `b=${dominant.b}`);
});
