//! HD1 bundle files: a zlib-chunked payload holding an index and resource entries.

use std::path::Path;

use crate::{KeplerError, Result};

pub const VERSION: u32 = 0xF000_0004;
const CHUNK: usize = 0x10000;
const PROPS: usize = 256;

#[derive(Debug, Clone, PartialEq)]
pub struct Variant {
    pub lang: u32,
    pub data: Vec<u8>,
    pub stream_size: u32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Entry {
    pub type_hash: u64,
    pub name_hash: u64,
    pub flags: u32,
    pub variants: Vec<Variant>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Bundle {
    pub props: [u8; PROPS],
    pub entries: Vec<Entry>,
}

/// Reads little-endian values from a byte slice, failing with `TruncatedBundle`.
struct Cursor<'a> {
    data: &'a [u8],
    pos: usize,
}

impl<'a> Cursor<'a> {
    fn take(&mut self, n: usize) -> Result<&'a [u8]> {
        let end = self.pos.checked_add(n).filter(|&e| e <= self.data.len()).ok_or(KeplerError::TruncatedBundle)?;
        let s = &self.data[self.pos..end];
        self.pos = end;
        Ok(s)
    }
    fn u32(&mut self) -> Result<u32> {
        Ok(u32::from_le_bytes(self.take(4)?.try_into().unwrap()))
    }
    fn u64(&mut self) -> Result<u64> {
        Ok(u64::from_le_bytes(self.take(8)?.try_into().unwrap()))
    }
}

/// Inflates chunks from `file` (header included) until `want` payload bytes are out, or all of them.
fn inflate(file: &[u8], want: Option<usize>) -> Result<Vec<u8>> {
    let mut c = Cursor { data: file, pos: 0 };
    let version = c.u32()?;
    if version != VERSION {
        return Err(KeplerError::BadBundleVersion(version));
    }
    let total = c.u32()? as usize;
    c.u32()?;
    let goal = want.map_or(total, |w| w.min(total));
    let mut out = Vec::with_capacity(goal);
    while out.len() < goal {
        let size = c.u32()? as usize;
        let chunk = c.take(size)?;
        if size == CHUNK {
            out.extend_from_slice(chunk);
        } else {
            use std::io::Read;
            flate2::read::ZlibDecoder::new(chunk).read_to_end(&mut out).map_err(|_| KeplerError::TruncatedBundle)?;
        }
    }
    out.truncate(total);
    Ok(out)
}

pub fn decompress(file: &[u8]) -> Result<Vec<u8>> {
    inflate(file, None)
}

pub fn compress(payload: &[u8]) -> Vec<u8> {
    use std::io::Write;
    let mut out = Vec::with_capacity(payload.len() / 2 + 64);
    out.extend(VERSION.to_le_bytes());
    out.extend((payload.len() as u32).to_le_bytes());
    out.extend(0u32.to_le_bytes());
    for piece in payload.chunks(CHUNK) {
        let mut block = piece.to_vec();
        block.resize(CHUNK, 0);
        let mut z = flate2::write::ZlibEncoder::new(Vec::new(), flate2::Compression::best());
        z.write_all(&block).unwrap();
        let z = z.finish().unwrap();
        let stored = z.len() >= CHUNK;
        let body = if stored { &block } else { &z };
        out.extend((body.len() as u32).to_le_bytes());
        out.extend_from_slice(body);
    }
    out
}

pub fn parse_payload(payload: &[u8]) -> Result<Bundle> {
    let mut c = Cursor { data: payload, pos: 0 };
    let count = c.u32()? as usize;
    let props: [u8; PROPS] = c.take(PROPS)?.try_into().unwrap();
    // The index repeats what each entry header says, so skip it.
    c.take(count.checked_mul(16).ok_or(KeplerError::TruncatedBundle)?)?;
    let mut entries = Vec::with_capacity(count);
    for _ in 0..count {
        let type_hash = c.u64()?;
        let name_hash = c.u64()?;
        let n = c.u32()? as usize;
        let flags = c.u32()?;
        let mut heads = Vec::with_capacity(n);
        for _ in 0..n {
            heads.push((c.u32()?, c.u32()? as usize, c.u32()?));
        }
        let variants = heads
            .into_iter()
            .map(|(lang, size, stream_size)| Ok(Variant { lang, data: c.take(size)?.to_vec(), stream_size }))
            .collect::<Result<Vec<_>>>()?;
        entries.push(Entry { type_hash, name_hash, flags, variants });
    }
    if payload[c.pos..].iter().any(|&b| b != 0) {
        return Err(KeplerError::TrailingData);
    }
    Ok(Bundle { props, entries })
}

impl Bundle {
    /// Sorts entries by (type, name), the order most vanilla bundles use.
    pub fn sort_entries(&mut self) {
        self.entries.sort_by_key(|e| (e.type_hash, e.name_hash));
    }
}

/// Writes entries in the order given: three vanilla bundles keep an unsorted index.
pub fn serialize_payload(b: &Bundle) -> Vec<u8> {
    let entries: Vec<&Entry> = b.entries.iter().collect();
    let mut out = Vec::new();
    out.extend((entries.len() as u32).to_le_bytes());
    out.extend_from_slice(&b.props);
    for e in &entries {
        out.extend(e.type_hash.to_le_bytes());
        out.extend(e.name_hash.to_le_bytes());
    }
    for e in &entries {
        out.extend(e.type_hash.to_le_bytes());
        out.extend(e.name_hash.to_le_bytes());
        out.extend((e.variants.len() as u32).to_le_bytes());
        out.extend(e.flags.to_le_bytes());
        for v in &e.variants {
            out.extend(v.lang.to_le_bytes());
            out.extend((v.data.len() as u32).to_le_bytes());
            out.extend(v.stream_size.to_le_bytes());
        }
        for v in &e.variants {
            out.extend_from_slice(&v.data);
        }
    }
    out
}

pub fn read_file(path: &Path) -> Result<Bundle> {
    parse_payload(&decompress(&std::fs::read(path)?)?)
}

pub fn write_file(path: &Path, b: &Bundle) -> Result<()> {
    std::fs::write(path, compress(&serialize_payload(b)))?;
    Ok(())
}

/// The (type, name) index, inflating only the chunks that hold it.
pub fn read_index(path: &Path) -> Result<Vec<(u64, u64)>> {
    let file = std::fs::read(path)?;
    let head = inflate(&file, Some(4))?;
    let count = u32::from_le_bytes(head[..4].try_into().map_err(|_| KeplerError::TruncatedBundle)?) as usize;
    let payload = inflate(&file, Some(4 + PROPS + count * 16))?;
    let mut c = Cursor { data: &payload, pos: 4 + PROPS };
    (0..count).map(|_| Ok((c.u64()?, c.u64()?))).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(type_hash: u64, name_hash: u64, flags: u32, data: &[u8]) -> Entry {
        Entry { type_hash, name_hash, flags, variants: vec![Variant { lang: 0, data: data.to_vec(), stream_size: 0 }] }
    }

    fn sample() -> Bundle {
        Bundle { props: [7u8; PROPS], entries: vec![entry(2, 9, 0, b"bb"), entry(1, 5, 531101911, b"aaaa")] }
    }

    #[test]
    fn payload_round_trips_in_given_order() {
        let p = serialize_payload(&sample());
        let back = parse_payload(&p).unwrap();
        assert_eq!(back, sample());
        assert_eq!(back.entries[1].flags, 531101911);
        assert_eq!(serialize_payload(&back), p);
    }

    #[test]
    fn sort_entries_orders_by_type_then_name() {
        let mut b = sample();
        b.sort_entries();
        assert_eq!((b.entries[0].type_hash, b.entries[1].type_hash), (1, 2));
    }

    #[test]
    fn file_round_trips_through_compression() {
        let mut b = sample();
        // An xorshift sequence does not compress, so this exercises stored chunks too.
        let mut x: u32 = 0x1234_5678;
        let noise: Vec<u8> = (0..200_000).map(|_| { x ^= x << 13; x ^= x >> 17; x ^= x << 5; x as u8 }).collect();
        b.entries.push(entry(3, 3, 0, &noise));
        let back = parse_payload(&decompress(&compress(&serialize_payload(&b))).unwrap()).unwrap();
        assert_eq!(back, b);
    }

    #[test]
    fn zero_padding_after_entries_is_accepted() {
        let mut p = serialize_payload(&sample());
        p.extend([0u8; 64]);
        assert_eq!(parse_payload(&p).unwrap().entries.len(), 2);
    }

    #[test]
    fn nonzero_trailing_data_is_rejected() {
        let mut p = serialize_payload(&sample());
        p.push(1);
        assert!(matches!(parse_payload(&p), Err(KeplerError::TrailingData)));
    }

    #[test]
    fn wrong_version_is_rejected() {
        let mut f = compress(&serialize_payload(&sample()));
        f[..4].copy_from_slice(&0xF000_0005u32.to_le_bytes());
        assert!(matches!(decompress(&f), Err(KeplerError::BadBundleVersion(0xF000_0005))));
    }

    #[test]
    fn index_reader_matches_full_parse() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("00000000000000aa");
        write_file(&path, &sample()).unwrap();
        let expected: Vec<_> = read_file(&path).unwrap().entries.iter().map(|e| (e.type_hash, e.name_hash)).collect();
        assert_eq!(read_index(&path).unwrap(), expected);
    }
}
