import sharp from 'sharp';

const THUMBNAIL_MAX_DIMENSION = 512;
// Guards against decompression-bomb style images (huge pixel dims, small file).
const MAX_INPUT_PIXELS = 60_000_000; // ~60MP

export interface ProcessedImage {
  originalBuffer: Buffer;
  thumbnailBuffer: Buffer;
  width: number;
  height: number;
}

/**
 * Re-encodes an uploaded image: strips all metadata (EXIF incl. GPS via a
 * blanket `.withMetadata()`-less pipeline), applies EXIF-aware auto-rotate,
 * and produces a bounded-size thumbnail. The re-encoded original is what
 * gets served - we never pass through the client's original bytes.
 */
export async function processImage(inputBuffer: Buffer): Promise<ProcessedImage> {
  const image = sharp(inputBuffer, { limitInputPixels: MAX_INPUT_PIXELS });
  const metadata = await image.rotate().metadata();

  // Re-encode to strip EXIF/GPS and any other embedded metadata. Not calling
  // .withMetadata() means sharp drops metadata by default.
  const originalBuffer = await sharp(inputBuffer, { limitInputPixels: MAX_INPUT_PIXELS })
    .rotate()
    .jpeg({ quality: 90, mozjpeg: true })
    .toBuffer();

  const thumbnailBuffer = await sharp(inputBuffer, { limitInputPixels: MAX_INPUT_PIXELS })
    .rotate()
    .resize({
      width: THUMBNAIL_MAX_DIMENSION,
      height: THUMBNAIL_MAX_DIMENSION,
      fit: 'inside',
      withoutEnlargement: true,
    })
    .jpeg({ quality: 80, mozjpeg: true })
    .toBuffer();

  const rotated = metadata.orientation && metadata.orientation >= 5;
  const width = (rotated ? metadata.height : metadata.width) ?? 0;
  const height = (rotated ? metadata.width : metadata.height) ?? 0;

  return { originalBuffer, thumbnailBuffer, width, height };
}
