export const avatarMaximumBytes = 327680;
const side = 256;
function crc32(bytes: Uint8Array): number {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) {
      crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}
/** Bounded RGB/RGBA pixels only: no EXIF, animation, interlacing or trailing data. */
export async function validateAvatarPng(bytes: Uint8Array): Promise<void> {
  const reject = () => {
    throw new Error("invalid_image");
  };
  if (bytes.length < 57 || bytes.length > avatarMaximumBytes) reject();
  if ([137, 80, 78, 71, 13, 10, 26, 10].some((byte, i) => bytes[i] !== byte)) {
    reject();
  }
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let offset = 8, channels = 0, ended = false;
  const compressed: Uint8Array[] = [];
  while (offset + 12 <= bytes.length && !ended) {
    const length = view.getUint32(offset);
    if (length > avatarMaximumBytes || offset + 12 + length > bytes.length) {
      reject();
    }
    const type = String.fromCharCode(...bytes.subarray(offset + 4, offset + 8));
    const data = bytes.subarray(offset + 8, offset + 8 + length);
    if (
      crc32(bytes.subarray(offset + 4, offset + 8 + length)) !==
        view.getUint32(offset + 8 + length)
    ) reject();
    if (type === "IHDR" && offset === 8 && length === 13) {
      if (
        view.getUint32(16) !== side || view.getUint32(20) !== side ||
        data[8] !== 8 ||
        ![2, 6].includes(data[9]) || data[10] !== 0 || data[11] !== 0 ||
        data[12] !== 0
      ) reject();
      channels = data[9] === 2 ? 3 : 4;
    } else if (type === "IDAT" && channels !== 0) compressed.push(data);
    else if (type === "IEND" && length === 0 && compressed.length > 0) {
      ended = true;
    } else reject();
    offset += length + 12;
  }
  if (!ended || offset !== bytes.length) reject();
  const expected = side * (side * channels + 1);
  const reader = new Blob(compressed).stream().pipeThrough(
    new DecompressionStream("deflate"),
  ).getReader();
  let received = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (received + value.length > expected) reject();
      for (let i = 0; i < value.length; i++) {
        if ((received + i) % (side * channels + 1) === 0 && value[i] > 4) {
          reject();
        }
      }
      received += value.length;
    }
    if (received !== expected) reject();
  } finally {
    await reader.cancel();
    reader.releaseLock();
  }
}
export async function readAvatarBody(request: Request): Promise<Uint8Array> {
  if (request.body == null) throw new Error("invalid_image");
  const reader = request.body.getReader();
  const parts: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > avatarMaximumBytes) throw new Error("invalid_image");
      parts.push(value);
    }
  } finally {
    await reader.cancel();
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const part of parts) {
    bytes.set(part, offset);
    offset += part.length;
  }
  try {
    await validateAvatarPng(bytes);
  } catch (_) {
    throw new Error("invalid_image");
  }
  return bytes;
}
