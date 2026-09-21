///| Black-box tests for Keccak-256.
///
/// The reference digests are published known-answer values for the empty
/// input, `abc`, and the quick-brown-fox sentence, plus boundary lengths that
/// exercise the padding rules. The boundary values and the four-byte
/// selectors were produced with pycryptodome's Keccak-256, which implements
/// the same original Keccak padding Ethereum uses.

///|
fn digest(text : String) -> String {
  @moonupgradeguard.hex_encode(@moonupgradeguard.keccak_256(@utf8.encode(text)))
}

///|
/// The four-byte selector Ethereum derives from a signature.
fn selector(signature : String) -> String {
  "0x" + digest(signature)[:8].to_owned()
}

///|
test "published known-answer digests" {
  assert_eq(
    digest(""),
    "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
  )
  assert_eq(
    digest("abc"),
    "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45",
  )
  assert_eq(
    digest("The quick brown fox jumps over the lazy dog"),
    "4d741b6f1eb29cb2a9b9911c82f56fa8d73b04959d3d9d222895df6c0b28aa15",
  )
}

///|
test "padding boundaries around the 136-byte rate" {
  assert_eq(
    digest("\u{0}".repeat(135)),
    "29e3704feeca7fb9ba229f0fa04d9b36449cf3ad6e1d85d9cfff3a10df9abc3e",
  )
  assert_eq(
    digest("\u{0}".repeat(136)),
    "3a5912a7c5faa06ee4fe906253e339467a9ce87d533c65be3c15cb231cdb25f9",
  )
  assert_eq(
    digest("\u{0}".repeat(137)),
    "bee7fbb405cb0d91a8775e338c4a5e4b5d6b2d051f687fa942043cffdc73bd28",
  )
  assert_eq(
    digest("a".repeat(200)),
    "96ea54061def936c4be90b518992fdc6f12f535068a256229aca54267b4d084d",
  )
}

///|
test "known Ethereum selectors" {
  assert_eq(selector("transfer(address,uint256)"), "0xa9059cbb")
  assert_eq(selector("balanceOf(address)"), "0x70a08231")
  assert_eq(selector("transferFrom(address,address,uint256)"), "0x23b872dd")
  assert_eq(selector("totalSupply()"), "0x18160ddd")
  assert_eq(selector("approve(address,uint256)"), "0x095ea7b3")
  assert_eq(
    selector("safeTransferFrom(address,address,uint256,bytes)"),
    "0xb88d4fde",
  )
}

///|
test "the published selector collision pair collides" {
  assert_eq(selector("burn(uint256)"), "0x42966c68")
  assert_eq(selector("collate_propagate_storage(bytes16)"), "0x42966c68")
}
