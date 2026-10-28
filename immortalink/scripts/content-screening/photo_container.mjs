const ascii = (b, pos, length) => String.fromCharCode(...b.subarray(pos, pos + length));

// Container/animation checks only. Pixel decoding and format validation belong
// to the established image library, not to this bounded header walk.
export function stillPhotoContainer(bytes, mime) {
  if (!(bytes instanceof Uint8Array) || bytes.length < 12) return false;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (mime === 'image/jpeg') {
    if (bytes[0] !== 255 || bytes[1] !== 216 || bytes[2] !== 255 ||
        bytes.at(-2) !== 255 || bytes.at(-1) !== 217) return false;
    for (let pos = 2; pos + 4 <= bytes.length;) {
      if (bytes[pos++] !== 255) return false;
      while (bytes[pos] === 255) pos++;
      const marker = bytes[pos++];
      if (marker === 218) return true; // Remaining entropy data is checked by decoder.
      if (marker === 217 || marker === undefined || marker === 0) return false;
      if (pos + 2 > bytes.length) return false;
      const length = view.getUint16(pos);
      if (length < 2 || length > bytes.length - pos) return false;
      if (marker === 226 && ascii(bytes, pos + 2, 4) === 'MPF\0') return false;
      pos += length;
    }
    return false;
  }
  if (mime === 'image/webp') {
    if (ascii(bytes, 0, 4) !== 'RIFF' || ascii(bytes, 8, 4) !== 'WEBP' || view.getUint32(4, true) + 8 !== bytes.length) return false;
    let pos = 12;
    for (; pos + 8 <= bytes.length;) {
      const kind = ascii(bytes, pos, 4), length = view.getUint32(pos + 4, true);
      if (length > bytes.length - pos - 8 || kind === 'ANIM' || kind === 'ANMF') return false;
      if (kind === 'VP8X' && (bytes[pos + 8] & 2)) return false;
      pos += 8 + length + (length % 2);
    }
    return pos === bytes.length;
  }
  if (mime !== 'image/png' || ![137, 80, 78, 71, 13, 10, 26, 10].every((v, i) => bytes[i] === v)) return false;
  for (let pos = 8; pos + 12 <= bytes.length;) {
    const length = view.getUint32(pos), kind = ascii(bytes, pos + 4, 4);
    if (length > bytes.length - pos - 12 || kind === 'acTL') return false;
    pos += length + 12;
    if (kind === 'IEND') return length === 0 && pos === bytes.length;
  }
  return false;
}
