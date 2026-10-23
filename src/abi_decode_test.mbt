///| Black-box tests for ABI decoding, exercised through artifact extraction.
///
/// The expected selectors and topics are Ethereum reference values, so these
/// tests also tie decoding to the Keccak vectors.

///|
/// Wraps an ABI array in a flat artifact that also carries an empty layout.
fn abi_artifact(abi : String) -> String {
  "{\"storageLayout\":{\"storage\":[],\"types\":{}},\"abi\":" + abi + "}"
}

///|
/// Decodes the ABI of a flat artifact that is expected to be valid.
fn decode(abi : String) -> @moonupgradeguard.Abi raise {
  let (artifact, diagnostics) = @moonupgradeguard.extract_artifact(
    abi_artifact(abi),
  )
  assert_eq(
    diagnostics.length(),
    0,
    msg="unexpected diagnostics:\n\{@moonupgradeguard.render_text(diagnostics)}",
  )
  match artifact {
    Some(artifact) =>
      match artifact.abi {
        Some(abi) => abi
        None => abort("artifact has no ABI")
      }
    None => abort("artifact extraction failed")
  }
}

///|
/// Extracts an artifact that is expected to fail, and renders why.
fn decode_report(abi : String) -> String {
  let (_, diagnostics) = @moonupgradeguard.extract_artifact(abi_artifact(abi))
  @moonupgradeguard.render_text(diagnostics)
}

///|
test "a function keeps its canonical signature and selector" {
  let abi = decode(
    "[{\"type\":\"function\",\"name\":\"transfer\",\"inputs\":[{\"name\":\"to\",\"type\":\"address\"},{\"name\":\"amount\",\"type\":\"uint256\"}],\"outputs\":[{\"name\":\"\",\"type\":\"bool\"}],\"stateMutability\":\"nonpayable\"}]",
  )
  assert_eq(abi.functions.length(), 1)
  let entry = abi.functions[0]
  assert_eq(entry.signature, "transfer(address,uint256)")
  assert_eq(entry.selector, "0xa9059cbb")
  assert_eq(entry.mutability, @moonupgradeguard.Mutability::NonPayable)
  assert_eq(entry.outputs.length(), 1)
  assert_eq(entry.outputs[0].type_name, "bool")
}

///|
test "tuples canonicalize from their components" {
  let abi = decode(
    "[{\"type\":\"function\",\"name\":\"batch\",\"inputs\":[{\"name\":\"items\",\"type\":\"tuple[]\",\"components\":[{\"name\":\"amount\",\"type\":\"uint256\"},{\"name\":\"to\",\"type\":\"address\"}]}],\"outputs\":[],\"stateMutability\":\"payable\"}]",
  )
  assert_eq(abi.functions[0].signature, "batch((uint256,address)[])")
  assert_eq(abi.functions[0].inputs[0].type_name, "(uint256,address)[]")
}

///|
test "an event keeps its topic and indexed flags" {
  let abi = decode(
    "[{\"type\":\"event\",\"name\":\"Transfer\",\"inputs\":[{\"name\":\"from\",\"type\":\"address\",\"indexed\":true},{\"name\":\"to\",\"type\":\"address\",\"indexed\":true},{\"name\":\"value\",\"type\":\"uint256\",\"indexed\":false}],\"anonymous\":false}]",
  )
  assert_eq(abi.events.length(), 1)
  let entry = abi.events[0]
  assert_eq(entry.signature, "Transfer(address,address,uint256)")
  assert_eq(
    entry.topic,
    "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",
  )
  assert_true(entry.inputs[0].indexed)
  assert_true(entry.inputs[1].indexed)
  assert_true(!entry.inputs[2].indexed)
  assert_true(!entry.anonymous)
}

///|
test "a custom error keeps its selector" {
  let abi = decode(
    "[{\"type\":\"error\",\"name\":\"InsufficientBalance\",\"inputs\":[{\"name\":\"available\",\"type\":\"uint256\"},{\"name\":\"required\",\"type\":\"uint256\"}]}]",
  )
  assert_eq(abi.errors.length(), 1)
  assert_eq(abi.errors[0].signature, "InsufficientBalance(uint256,uint256)")
  assert_eq(abi.errors[0].selector, "0xcf479181")
}

///|
test "fallback and receive normalize without parameters" {
  let abi = decode(
    "[{\"type\":\"fallback\",\"stateMutability\":\"payable\"},{\"type\":\"receive\",\"stateMutability\":\"payable\"}]",
  )
  assert_eq(abi.functions.length(), 2)
  assert_eq(abi.functions[0].signature, "fallback()")
  assert_eq(abi.functions[0].kind, @moonupgradeguard.AbiEntryKind::Fallback)
  assert_eq(abi.functions[1].signature, "receive()")
  assert_eq(abi.functions[1].kind, @moonupgradeguard.AbiEntryKind::Receive)
  assert_eq(abi.functions[1].mutability, @moonupgradeguard.Mutability::Payable)
}

///|
test "receive rejects nonpayable view and pure mutability" {
  for mutability in ["nonpayable", "view", "pure"] {
    inspect(
      decode_report(
        "[{\"type\":\"receive\",\"stateMutability\":\"" + mutability + "\"}]",
      ),
      content=(
        #|error[artifact.field.invalid] $.abi[0].stateMutability: receive entry must be payable
        #|
      ),
    )
  }
}

///|
test "fallback rejects view and pure mutability" {
  for mutability in ["view", "pure"] {
    inspect(
      decode_report(
        "[{\"type\":\"fallback\",\"stateMutability\":\"" + mutability + "\"}]",
      ),
      content=(
        #|error[artifact.field.invalid] $.abi[0].stateMutability: fallback entry must be nonpayable or payable
        #|
      ),
    )
  }
}

///|
test "fallback accepts both payable and nonpayable mutability" {
  let abi = decode(
    "[{\"type\":\"fallback\",\"stateMutability\":\"nonpayable\"}]",
  )
  assert_eq(
    abi.functions[0].mutability,
    @moonupgradeguard.Mutability::NonPayable,
  )
}

///|
test "named functions including receive and fallback retain all mutabilities" {
  for name in ["receive", "fallback", "f"] {
    for mutability in ["pure", "view", "nonpayable", "payable"] {
      let abi = decode(
        "[{\"type\":\"function\",\"name\":\"" +
        name +
        "\",\"inputs\":[],\"outputs\":[],\"stateMutability\":\"" +
        mutability +
        "\"}]",
      )
      assert_eq(abi.functions[0].kind, @moonupgradeguard.AbiEntryKind::Function)
      assert_eq(abi.functions[0].name, name)
    }
  }
}

///|
test "a constructor is not part of the callable interface" {
  let abi = decode(
    "[{\"type\":\"constructor\",\"inputs\":[{\"name\":\"owner\",\"type\":\"address\"}],\"stateMutability\":\"nonpayable\"}]",
  )
  assert_eq(abi.functions.length(), 0)
  assert_eq(abi.events.length(), 0)
  assert_eq(abi.errors.length(), 0)
}

///|
test "an artifact without an ABI is not an error" {
  let (artifact, diagnostics) = @moonupgradeguard.extract_artifact(
    "{\"storageLayout\":{\"storage\":[],\"types\":{}}}",
  )
  assert_eq(diagnostics.length(), 0)
  match artifact {
    Some(artifact) => assert_true(artifact.abi is None)
    None => abort("artifact extraction failed")
  }
}

///|
test "a non-canonical type name is rejected" {
  inspect(
    decode_report(
      "[{\"type\":\"function\",\"name\":\"f\",\"inputs\":[{\"type\":\"uint\"}],\"outputs\":[],\"stateMutability\":\"view\"}]",
    ),
    content=(
      #|error[artifact.field.invalid] $.abi[0].inputs[0].type: unsupported ABI type "uint"
      #|
    ),
  )
}

///|
test "zero-padded elementary widths are rejected before signature hashing" {
  for
    type_name in ["uint0256", "int08", "bytes01", "uint0008[]", "bytes032[2][]"] {
    let (_, diagnostics) = @moonupgradeguard.extract_artifact(
      abi_artifact(
        "[{\"type\":\"function\",\"name\":\"f\",\"inputs\":[{\"type\":\"" +
        type_name +
        "\"}],\"outputs\":[],\"stateMutability\":\"view\"}]",
      ),
    )
    assert_eq(diagnostics.length(), 1)
    assert_eq(
      diagnostics[0].code,
      @moonupgradeguard.DiagnosticCode::ArtifactFieldInvalid,
    )
    assert_eq(diagnostics[0].location.path, "$.abi[0].inputs[0].type")
  }
}

///|
test "zero-padded array dimensions are rejected before signature hashing" {
  for type_name in ["uint256[01]", "bytes32[][002]", "int8[2][00]"] {
    let (_, diagnostics) = @moonupgradeguard.extract_artifact(
      abi_artifact(
        "[{\"type\":\"function\",\"name\":\"f\",\"inputs\":[{\"type\":\"" +
        type_name +
        "\"}],\"outputs\":[],\"stateMutability\":\"view\"}]",
      ),
    )
    assert_eq(diagnostics.length(), 1)
    assert_eq(
      diagnostics[0].code,
      @moonupgradeguard.DiagnosticCode::ArtifactFieldInvalid,
    )
    assert_eq(diagnostics[0].location.path, "$.abi[0].inputs[0].type")
  }
}

///|
test "tuple arrays reject zero-padded outer dimensions" {
  inspect(
    decode_report(
      "[{\"type\":\"function\",\"name\":\"f\",\"inputs\":[{\"type\":\"tuple[01][]\",\"components\":[{\"type\":\"uint256\"}]}],\"outputs\":[],\"stateMutability\":\"view\"}]",
    ),
    content=(
      #|error[artifact.field.invalid] $.abi[0].inputs[0].type: unsupported array type "tuple[01][]"
      #|
    ),
  )
}

///|
test "canonical array dimensions remain lossless including zero and large sizes" {
  for
    type_name in ["uint256[]", "uint256[0]", "bytes32[][2]", "int8[2147483648]"] {
    let abi = decode(
      "[{\"type\":\"function\",\"name\":\"f\",\"inputs\":[{\"type\":\"" +
      type_name +
      "\"}],\"outputs\":[],\"stateMutability\":\"view\"}]",
    )
    assert_eq(abi.functions[0].signature, "f(" + type_name + ")")
  }
}

///|
test "canonical elementary width boundaries retain their signatures" {
  for
    type_name in [
      "uint8", "uint256", "int8", "int256", "bytes1", "bytes32", "bytes32[2][]",
    ] {
    let abi = decode(
      "[{\"type\":\"function\",\"name\":\"f\",\"inputs\":[{\"type\":\"" +
      type_name +
      "\"}],\"outputs\":[],\"stateMutability\":\"view\"}]",
    )
    assert_eq(abi.functions[0].signature, "f(" + type_name + ")")
  }
}

///|
test "an impossible integer width is rejected" {
  inspect(
    decode_report(
      "[{\"type\":\"function\",\"name\":\"f\",\"inputs\":[{\"type\":\"uint7\"}],\"outputs\":[],\"stateMutability\":\"view\"}]",
    ),
    content=(
      #|error[artifact.field.invalid] $.abi[0].inputs[0].type: unsupported ABI type "uint7"
      #|
    ),
  )
}

///|
test "an impossible fixed-bytes width is rejected" {
  inspect(
    decode_report(
      "[{\"type\":\"function\",\"name\":\"f\",\"inputs\":[{\"type\":\"bytes33\"}],\"outputs\":[],\"stateMutability\":\"view\"}]",
    ),
    content=(
      #|error[artifact.field.invalid] $.abi[0].inputs[0].type: unsupported ABI type "bytes33"
      #|
    ),
  )
}

///|
test "a tuple without components is rejected" {
  inspect(
    decode_report(
      "[{\"type\":\"function\",\"name\":\"f\",\"inputs\":[{\"type\":\"tuple\"}],\"outputs\":[],\"stateMutability\":\"view\"}]",
    ),
    content=(
      #|error[artifact.field.invalid] $.abi[0].inputs[0].components: a tuple type needs components
      #|
    ),
  )
}

///|
test "legacy mutability fields are rejected instead of guessed" {
  inspect(
    decode_report(
      "[{\"type\":\"function\",\"name\":\"f\",\"inputs\":[],\"outputs\":[],\"constant\":true,\"payable\":false}]",
    ),
    content=(
      #|error[artifact.field.invalid] $.abi[0].stateMutability: legacy ABI mutability fields are not supported; recompile with Solidity 0.5 or later
      #|
    ),
  )
}

///|
test "an unknown entry kind is reported" {
  inspect(
    decode_report("[{\"type\":\"struct\",\"name\":\"S\"}]"),
    content=(
      #|error[artifact.field.invalid] $.abi[0].type: unsupported ABI entry type "struct"
      #|
    ),
  )
}

///|
test "a non-array abi is reported" {
  inspect(
    decode_report("{}"),
    content=(
      #|error[artifact.field.invalid] $.abi: expected a JSON array
      #|
    ),
  )
}

///|
test "an indexed flag of the wrong type is reported" {
  inspect(
    decode_report(
      "[{\"type\":\"event\",\"name\":\"E\",\"inputs\":[{\"type\":\"uint256\",\"indexed\":\"yes\"}]}]",
    ),
    content=(
      #|error[artifact.field.invalid] $.abi[0].inputs[0].indexed: expected a boolean
      #|
    ),
  )
}

///|
test "a function input list is required" {
  inspect(
    decode_report(
      "[{\"type\":\"function\",\"name\":\"f\",\"outputs\":[],\"stateMutability\":\"view\"}]",
    ),
    content=(
      #|error[artifact.field.invalid] $.abi[0].inputs: required field is missing
      #|
    ),
  )
}

///|
test "a function output list is required" {
  inspect(
    decode_report(
      "[{\"type\":\"function\",\"name\":\"f\",\"inputs\":[],\"stateMutability\":\"view\"}]",
    ),
    content=(
      #|error[artifact.field.invalid] $.abi[0].outputs: required field is missing
      #|
    ),
  )
}

///|
test "event indexed and anonymous fields are required" {
  inspect(
    decode_report(
      "[{\"type\":\"event\",\"name\":\"E\",\"inputs\":[{\"name\":\"value\",\"type\":\"uint256\"}],\"anonymous\":false}]",
    ),
    content=(
      #|error[artifact.field.invalid] $.abi[0].inputs[0].indexed: required field is missing
      #|
    ),
  )
  inspect(
    decode_report("[{\"type\":\"event\",\"name\":\"E\",\"inputs\":[]}]"),
    content=(
      #|error[artifact.field.invalid] $.abi[0].anonymous: required field is missing
      #|
    ),
  )
}
