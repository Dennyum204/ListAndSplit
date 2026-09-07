function chunk(type: string, data: Uint8Array) {
  const bytes = new Uint8Array(data.length + 12);
  const view = new DataView(bytes.buffer);
  view.setUint32(0, data.length);
  bytes.set(new TextEncoder().encode(type), 4);
  bytes.set(data, 8);
  let crc = 0xffffffff;
  for (const byte of bytes.subarray(4, 8 + data.length)) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) {
      crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
  }
  view.setUint32(data.length + 8, (crc ^ 0xffffffff) >>> 0);
  return bytes;
}
export async function png(
  options: {
    width?: number;
    rows?: number;
    filter?: number;
    metadata?: boolean;
    badDeflate?: boolean;
  } = {},
) {
  const header = new Uint8Array(13), view = new DataView(header.buffer);
  view.setUint32(0, options.width ?? 256);
  view.setUint32(4, 256);
  header[8] = 8;
  header[9] = 6;
  const pixels = new Uint8Array((options.rows ?? 256) * 1025);
  pixels[0] = options.filter ?? 0;
  const compressed = options.badDeflate
    ? new Uint8Array([1, 2, 3])
    : new Uint8Array(
      await new Response(
        new Blob([pixels]).stream().pipeThrough(
          new CompressionStream("deflate"),
        ),
      ).arrayBuffer(),
    );
  return new Uint8Array(
    await new Blob([
      new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]),
      chunk("IHDR", header),
      ...(options.metadata
        ? [chunk("tEXt", new TextEncoder().encode("GPS\0never upload"))]
        : []),
      chunk("IDAT", compressed),
      chunk("IEND", new Uint8Array()),
    ]).arrayBuffer(),
  );
}
