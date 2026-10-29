//! Lua resources: LuaJIT 2.0 bytecode inside the game's small length envelope.

use crate::{ObsidianError, Result};

const MAGIC: [u8; 4] = [0x1b, 0x4c, 0x4a, 0x01];
const FLAG_BIG_ENDIAN: u8 = 0x01;

/// Accepts LuaJIT 2.0 bytecode only: the game rejects source and 2.1 bytecode.
pub fn check_bytecode(code: &[u8]) -> Result<()> {
    if code.len() < 5 || code[..3] != MAGIC[..3] {
        return Err(ObsidianError::InvalidBytecode("not LuaJIT bytecode (plain source cannot run in the game)".into()));
    }
    if code[3] != MAGIC[3] {
        return Err(ObsidianError::InvalidBytecode(format!("bytecode version {} is not LuaJIT 2.0", code[3])));
    }
    if code[4] & FLAG_BIG_ENDIAN != 0 {
        return Err(ObsidianError::InvalidBytecode("big-endian bytecode".into()));
    }
    Ok(())
}

pub fn wrap_resource(code: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(code.len() + 8);
    out.extend((code.len() as u32).to_le_bytes());
    out.extend(2u32.to_le_bytes());
    out.extend_from_slice(code);
    out
}

pub fn unwrap_resource(res: &[u8]) -> Result<&[u8]> {
    let bad = || ObsidianError::InvalidBytecode("not a lua resource envelope".into());
    let len = u32::from_le_bytes(res.get(..4).ok_or_else(bad)?.try_into().unwrap()) as usize;
    let kind = u32::from_le_bytes(res.get(4..8).ok_or_else(bad)?.try_into().unwrap());
    if kind != 2 || res.len() != len + 8 {
        return Err(bad());
    }
    Ok(&res[8..])
}

#[cfg(test)]
mod tests {
    use super::*;

    const VANILLA_BODY_HEX: &str = "1b4c4a0102450200020003000434000000250102003a0101004700010018323032302d31322d32322030393a33333a31341b4255494c445f444154455f494e464f524d4154494f4e075f4700";

    fn hex(s: &str) -> Vec<u8> {
        (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap()).collect()
    }

    #[test]
    fn vanilla_bytecode_passes_and_wraps() {
        let body = hex(VANILLA_BODY_HEX);
        check_bytecode(&body).unwrap();
        let res = wrap_resource(&body);
        assert_eq!(&res[..8], &[76, 0, 0, 0, 2, 0, 0, 0]);
        assert_eq!(unwrap_resource(&res).unwrap(), &body[..]);
    }

    #[test]
    fn source_text_and_luajit21_are_rejected() {
        assert!(check_bytecode(b"return 1").is_err());
        assert!(check_bytecode(&[0x1b, 0x4c, 0x4a, 0x02, 0x02]).is_err());
    }
}
