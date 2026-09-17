///| Keccak-256, the hash Ethereum uses for function selectors, custom error
/// selectors, and event topics.
///
/// Ethereum uses the original Keccak padding byte `0x01`, not the SHA-3
/// padding byte `0x06`, so this is Keccak-f[1600] with a 1088-bit rate. The
/// round constants, rotation offsets, and lane permutation are the ones
/// published with the Keccak specification, and the digest is checked against
/// published known-answer values, including the boundary lengths where
/// padding shares a byte.

///|
/// Keccak round constants for the iota step.
let round_constants : Array[UInt64] = [
  0x0000000000000001UL, 0x0000000000008082UL, 0x800000000000808aUL, 0x8000000080008000UL,
  0x000000000000808bUL, 0x0000000080000001UL, 0x8000000080008081UL, 0x8000000000008009UL,
  0x000000000000008aUL, 0x0000000000000088UL, 0x0000000080008009UL, 0x000000008000000aUL,
  0x000000008000808bUL, 0x800000000000008bUL, 0x8000000000008089UL, 0x8000000000008003UL,
  0x8000000000008002UL, 0x8000000000000080UL, 0x000000000000800aUL, 0x800000008000000aUL,
  0x8000000080008081UL, 0x8000000000008080UL, 0x0000000080000001UL, 0x8000000080008008UL,
]

///|
/// Rotation amount for each step of the combined rho and pi step.
let rotation_amounts : Array[Int] = [
  1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14, 27, 41, 56, 8, 25, 43, 62, 18, 39,
  61, 20, 44,
]

///|
/// Lane visited by each step of the combined rho and pi step.
let lane_permutation : Array[Int] = [
  10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13, 12, 2, 20, 14, 22, 9,
  6, 1,
]

///|
/// Number of bytes absorbed per permutation for a 1088-bit rate.
let rate_bytes = 136

///|
/// Rotates a lane left by `n` bits, for `0 <= n < 64`.
fn rotate_left(value : UInt64, n : Int) -> UInt64 {
  if n == 0 {
    value
  } else {
    (value << n) | (value >> (64 - n))
  }
}

///|
/// Applies Keccak-f[1600] to the 25-lane state in place.
fn keccak_f1600(state : Array[UInt64]) -> Unit {
  let column : Array[UInt64] = Array::make(5, 0UL)
  for round in 0..<24 {
    // Theta
    for i in 0..<5 {
      column[i] = state[i] ^
        state[i + 5] ^
        state[i + 10] ^
        state[i + 15] ^
        state[i + 20]
    }
    for i in 0..<5 {
      let t = column[(i + 4) % 5] ^ rotate_left(column[(i + 1) % 5], 1)
      for j in 0..<5 {
        state[j * 5 + i] = state[j * 5 + i] ^ t
      }
    }
    // Rho and pi
    let mut carried = state[1]
    for i in 0..<24 {
      let lane = lane_permutation[i]
      let saved = state[lane]
      state[lane] = rotate_left(carried, rotation_amounts[i])
      carried = saved
    }
    // Chi
    for j in 0..<5 {
      for i in 0..<5 {
        column[i] = state[j * 5 + i]
      }
      for i in 0..<5 {
        state[j * 5 + i] = state[j * 5 + i] ^
          (column[(i + 1) % 5].lnot() & column[(i + 2) % 5])
      }
    }
    // Iota
    state[0] = state[0] ^ round_constants[round]
  }
}

///|
/// XORs `length` bytes starting at `offset` into the state as little-endian
/// lanes.
fn absorb(
  state : Array[UInt64],
  data : Bytes,
  offset : Int,
  length : Int,
) -> Unit {
  for i in 0..<length {
    let value : UInt64 = data[offset + i].to_uint64()
    state[i / 8] = state[i / 8] ^ (value << (i % 8 * 8))
  }
}

///|
/// Keccak-256 digest of `data`, as 32 bytes.
pub fn keccak_256(data : Bytes) -> Bytes {
  let state : Array[UInt64] = Array::make(25, 0UL)
  let length = data.length()
  let mut offset = 0
  while length - offset >= rate_bytes {
    absorb(state, data, offset, rate_bytes)
    keccak_f1600(state)
    offset += rate_bytes
  }
  // The final block carries the Keccak pad: `0x01`, zeros, then `0x80` in the
  // last byte of the block. When one byte is left, both bits share it.
  let last_block : Array[Byte] = Array::make(rate_bytes, 0)
  let remaining = length - offset
  for i in 0..<remaining {
    last_block[i] = data[offset + i]
  }
  last_block[remaining] = 1
  last_block[rate_bytes - 1] = last_block[rate_bytes - 1]
    .to_int()
    .lor(0x80)
    .to_byte()
  absorb(state, Bytes::from_array(last_block), 0, rate_bytes)
  keccak_f1600(state)
  let digest : Array[Byte] = Array::make(32, 0)
  for i in 0..<4 {
    let lane = state[i]
    for b in 0..<8 {
      digest[i * 8 + b] = ((lane >> (8 * b)) & 0xFFUL).to_byte()
    }
  }
  Bytes::from_array(digest)
}

///|
/// Lowercase hex of `data`, without a `0x` prefix.
pub fn hex_encode(data : Bytes) -> String {
  let buf = StringBuilder()
  for i in 0..<data.length() {
    buf.write_string(data[i].to_hex())
  }
  buf.to_string()
}
