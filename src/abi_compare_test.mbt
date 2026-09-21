///| Black-box tests for the ABI compatibility engine.
///
/// The fixtures are model values rather than compiler output: comparison is a
/// pure function, and building the model directly keeps each rule visible. ABI
/// decoding is covered by `abi_decode_test.mbt`.

///|
fn abi_param(type_name : String) -> @moonupgradeguard.AbiParam {
  { name: "", type_name, indexed: false, }
}

///|
fn abi_indexed(type_name : String) -> @moonupgradeguard.AbiParam {
  { name: "", type_name, indexed: true, }
}

///|
/// The hex digest of a signature, so hand-built fixtures carry the same
/// selectors and topics that decoding would produce.
fn signature_digest(signature : String) -> String {
  hex_encode(keccak_256(@utf8.encode(signature)))
}

///|
fn signature_name(signature : String) -> String {
  match signature.find("(") {
    Some(index) => signature[:index].to_owned()
    None => signature
  }
}

///|
fn abi_function(
  signature : String,
  mutability : @moonupgradeguard.Mutability,
) -> @moonupgradeguard.AbiFunction {
  {
    kind: @moonupgradeguard.AbiEntryKind::Function,
    name: signature_name(signature),
    signature,
    selector: "0x" + signature_digest(signature)[:8].to_owned(),
    inputs: [],
    outputs: [],
    mutability,
  }
}

///|
fn abi_fallback() -> @moonupgradeguard.AbiFunction {
  {
    kind: @moonupgradeguard.AbiEntryKind::Fallback,
    name: "",
    signature: "fallback()",
    selector: "",
    inputs: [],
    outputs: [],
    mutability: @moonupgradeguard.Mutability::Payable,
  }
}

///|
fn abi_event(signature : String) -> @moonupgradeguard.AbiEvent {
  {
    name: signature_name(signature),
    signature,
    topic: "0x" + signature_digest(signature),
    inputs: [],
    anonymous: false,
  }
}

///|
fn abi_error(
  signature : String,
  selector : String,
) -> @moonupgradeguard.AbiError {
  { name: signature_name(signature), signature, selector, inputs: [], }
}

///|
fn abi_of(
  functions : Array[@moonupgradeguard.AbiFunction],
  events : Array[@moonupgradeguard.AbiEvent],
  errors : Array[@moonupgradeguard.AbiError],
) -> @moonupgradeguard.Abi {
  { functions, events, errors, }
}

///|
fn abi_report(
  old : @moonupgradeguard.Abi,
  new : @moonupgradeguard.Abi,
) -> String {
  @moonupgradeguard.render_text(@moonupgradeguard.compare_abi(old, new))
}

///|
test "an unchanged ABI is compatible" {
  let abi = abi_of(
    [abi_function("transfer(address,uint256)", NonPayable)],
    [abi_event("Transfer(address,address,uint256)")],
    [abi_error("Bad(uint256)", "0xdeadbeef")],
  )
  inspect(abi_report(abi, abi), content="")
  assert_true(
    !@moonupgradeguard.blocks_upgrade(@moonupgradeguard.compare_abi(abi, abi)),
  )
}

///|
test "entry order does not matter" {
  let first = abi_of(
    [abi_function("a()", View), abi_function("b()", View)],
    [],
    [],
  )
  let second = abi_of(
    [abi_function("b()", View), abi_function("a()", View)],
    [],
    [],
  )
  assert_eq(abi_report(first, first), "")
  assert_eq(abi_report(first, second), "")
}

///|
test "a removed function is an error" {
  let old = abi_of(
    [abi_function("transfer(address,uint256)", NonPayable)],
    [],
    [],
  )
  let new = abi_of([], [], [])
  inspect(
    abi_report(old, new),
    content=(
      #|error[abi.function.removed] abi.functions: function "transfer(address,uint256)" is missing from the new ABI (old: transfer(address,uint256))
      #|
    ),
  )
  assert_true(
    @moonupgradeguard.blocks_upgrade(@moonupgradeguard.compare_abi(old, new)),
  )
}

///|
test "an added function is information only" {
  let old = abi_of([], [], [])
  let new = abi_of(
    [abi_function("transfer(address,uint256)", NonPayable)],
    [],
    [],
  )
  inspect(
    abi_report(old, new),
    content=(
      #|info[abi.function.added] abi.functions: function "transfer(address,uint256)" was added to the new ABI (new: transfer(address,uint256))
      #|
    ),
  )
  assert_true(
    !@moonupgradeguard.blocks_upgrade(@moonupgradeguard.compare_abi(old, new)),
  )
}

///|
test "losing the static-call guarantee is an error" {
  let old = abi_of([abi_function("totalSupply()", View)], [], [])
  let new = abi_of([abi_function("totalSupply()", NonPayable)], [], [])
  inspect(
    abi_report(old, new),
    content=(
      #|error[abi.function.mutability.incompatible] abi.functions["totalSupply()"].stateMutability: function "totalSupply()" changed state mutability from "view" to "nonpayable" (old: view, new: nonpayable)
      #|
    ),
  )
  assert_true(
    @moonupgradeguard.blocks_upgrade(@moonupgradeguard.compare_abi(old, new)),
  )
}

///|
test "losing payability is an error" {
  let old = abi_of([abi_function("deposit()", Payable)], [], [])
  let new = abi_of([abi_function("deposit()", NonPayable)], [], [])
  let diagnostics = @moonupgradeguard.compare_abi(old, new)
  assert_eq(
    diagnostics[0].code,
    @moonupgradeguard.DiagnosticCode::AbiFunctionMutabilityIncompatible,
  )
  assert_true(@moonupgradeguard.blocks_upgrade(diagnostics))
}

///|
test "gaining payability remains a warning" {
  let old = abi_of([abi_function("deposit()", NonPayable)], [], [])
  let new = abi_of([abi_function("deposit()", Payable)], [], [])
  let diagnostics = @moonupgradeguard.compare_abi(old, new)
  assert_eq(
    diagnostics[0].code,
    @moonupgradeguard.DiagnosticCode::AbiFunctionMutabilityChanged,
  )
  assert_true(!@moonupgradeguard.blocks_upgrade(diagnostics))
}

///|
test "a changed output type is an error" {
  let old = abi_of(
    [
      {
        ..abi_function("totalSupply()", View),
        outputs: [abi_param("uint256")],
      },
    ],
    [],
    [],
  )
  let new = abi_of(
    [{ ..abi_function("totalSupply()", View), outputs: [abi_param("bool")], }],
    [],
    [],
  )
  inspect(
    abi_report(old, new),
    content=(
      #|error[abi.function.outputs.changed] abi.functions["totalSupply()"].outputs: function "totalSupply()" changed its output types from "uint256" to "bool" (old: uint256, new: bool)
      #|
    ),
  )
  assert_true(
    @moonupgradeguard.blocks_upgrade(@moonupgradeguard.compare_abi(old, new)),
  )
}

///|
test "an added output is an error because callers decode positionally" {
  let old = abi_of(
    [{ ..abi_function("get()", View), outputs: [abi_param("uint256")], }],
    [],
    [],
  )
  let new = abi_of(
    [
      {
        ..abi_function("get()", View),
        outputs: [abi_param("uint256"), abi_param("uint256")],
      },
    ],
    [],
    [],
  )
  inspect(
    abi_report(old, new),
    content=(
      #|error[abi.function.outputs.changed] abi.functions["get()"].outputs: function "get()" changed its output types from "uint256" to "uint256,uint256" (old: uint256, new: uint256,uint256)
      #|
    ),
  )
  assert_true(
    @moonupgradeguard.blocks_upgrade(@moonupgradeguard.compare_abi(old, new)),
  )
}

///|
test "reordering parameters changes the signature" {
  let old = abi_of([abi_function("f(uint256,address)", NonPayable)], [], [])
  let new = abi_of([abi_function("f(address,uint256)", NonPayable)], [], [])
  inspect(
    abi_report(old, new),
    content=(
      #|info[abi.function.added] abi.functions: function "f(address,uint256)" was added to the new ABI (new: f(address,uint256))
      #|error[abi.function.removed] abi.functions: function "f(uint256,address)" is missing from the new ABI (old: f(uint256,address))
      #|
    ),
  )
  assert_true(
    @moonupgradeguard.blocks_upgrade(@moonupgradeguard.compare_abi(old, new)),
  )
}

///|
test "an event removal is an error" {
  let old = abi_of([], [abi_event("Transfer(address,address,uint256)")], [])
  let new = abi_of([], [], [])
  inspect(
    abi_report(old, new),
    content=(
      #|error[abi.event.removed] abi.events: event "Transfer(address,address,uint256)" is missing from the new ABI (old: Transfer(address,address,uint256))
      #|
    ),
  )
  assert_true(
    @moonupgradeguard.blocks_upgrade(@moonupgradeguard.compare_abi(old, new)),
  )
}

///|
test "an event addition is information only" {
  let old = abi_of([], [], [])
  let new = abi_of([], [abi_event("Transfer(address,address,uint256)")], [])
  inspect(
    abi_report(old, new),
    content=(
      #|info[abi.event.added] abi.events: event "Transfer(address,address,uint256)" was added to the new ABI (new: Transfer(address,address,uint256))
      #|
    ),
  )
  assert_true(
    !@moonupgradeguard.blocks_upgrade(@moonupgradeguard.compare_abi(old, new)),
  )
}

///|
test "an indexed change is an error" {
  let old = abi_of(
    [],
    [
      {
        ..abi_event("Transfer(address,address,uint256)"),
        inputs: [
          abi_indexed("address"),
          abi_indexed("address"),
          abi_param("uint256"),
        ],
      },
    ],
    [],
  )
  let new = abi_of(
    [],
    [
      {
        ..abi_event("Transfer(address,address,uint256)"),
        inputs: [
          abi_indexed("address"),
          abi_param("address"),
          abi_param("uint256"),
        ],
      },
    ],
    [],
  )
  inspect(
    abi_report(old, new),
    content=(
      #|error[abi.event.indexed.changed] abi.events["Transfer(address,address,uint256)"].inputs: event "Transfer(address,address,uint256)" changed its indexed parameters from "indexed, indexed, not indexed" to "indexed, not indexed, not indexed" (old: indexed, indexed, not indexed, new: indexed, not indexed, not indexed)
      #|
    ),
  )
  assert_true(
    @moonupgradeguard.blocks_upgrade(@moonupgradeguard.compare_abi(old, new)),
  )
}

///|
test "an anonymity change is an error" {
  let old = abi_of([], [abi_event("Ping(uint256)")], [])
  let new = abi_of([], [{ ..abi_event("Ping(uint256)"), anonymous: true, }], [])
  inspect(
    abi_report(old, new),
    content=(
      #|error[abi.event.anonymous.changed] abi.events["Ping(uint256)"].anonymous: event "Ping(uint256)" changed from anonymous=false to anonymous=true (old: false, new: true)
      #|
    ),
  )
  assert_true(
    @moonupgradeguard.blocks_upgrade(@moonupgradeguard.compare_abi(old, new)),
  )
}

///|
test "an error removal is an error and an addition is information" {
  let old = abi_of([], [], [abi_error("Bad(uint256)", "0xdeadbeef")])
  let new = abi_of([], [], [abi_error("Worse(bytes32)", "0xfeedface")])
  inspect(
    abi_report(old, new),
    content=(
      #|info[abi.error.added] abi.errors: error "Worse(bytes32)" was added to the new ABI (new: Worse(bytes32))
      #|error[abi.error.removed] abi.errors: error "Bad(uint256)" is missing from the new ABI (old: Bad(uint256))
      #|
    ),
  )
  assert_true(
    @moonupgradeguard.blocks_upgrade(@moonupgradeguard.compare_abi(old, new)),
  )
}

///|
test "a named function does not replace a fallback handler" {
  let old = abi_of([abi_fallback()], [], [])
  let new = abi_of(
    [abi_function("fallback()", @moonupgradeguard.Mutability::Payable)],
    [],
    [],
  )
  inspect(
    abi_report(old, new),
    content=(
      #|info[abi.function.added] abi.functions: function "fallback()" was added to the new ABI (new: fallback())
      #|error[abi.function.removed] abi.functions: fallback "fallback()" is missing from the new ABI (old: fallback())
      #|
    ),
  )
  assert_true(
    @moonupgradeguard.blocks_upgrade(@moonupgradeguard.compare_abi(old, new)),
  )
}

///|
test "a named function does not replace a receive handler" {
  let old = abi_of(
    [
      {
        kind: @moonupgradeguard.AbiEntryKind::Receive,
        name: "",
        signature: "receive()",
        selector: "",
        inputs: [],
        outputs: [],
        mutability: @moonupgradeguard.Mutability::Payable,
      },
    ],
    [],
    [],
  )
  let new = abi_of(
    [abi_function("receive()", @moonupgradeguard.Mutability::Payable)],
    [],
    [],
  )
  inspect(
    abi_report(old, new),
    content=(
      #|info[abi.function.added] abi.functions: function "receive()" was added to the new ABI (new: receive())
      #|error[abi.function.removed] abi.functions: receive "receive()" is missing from the new ABI (old: receive())
      #|
    ),
  )
  assert_true(
    @moonupgradeguard.blocks_upgrade(@moonupgradeguard.compare_abi(old, new)),
  )
}

///|
test "a removed fallback is an error" {
  let old = abi_of([abi_fallback()], [], [])
  let new = abi_of([], [], [])
  inspect(
    abi_report(old, new),
    content=(
      #|error[abi.function.removed] abi.functions: fallback "fallback()" is missing from the new ABI (old: fallback())
      #|
    ),
  )
  assert_true(
    @moonupgradeguard.blocks_upgrade(@moonupgradeguard.compare_abi(old, new)),
  )
}

///|
test "a selector handed to another signature is an error" {
  // `burn(uint256)` and `collate_propagate_storage(bytes16)` are a published
  // four-byte selector collision.
  let old = abi_of(
    [{ ..abi_function("burn(uint256)", NonPayable), selector: "0x42966c68", }],
    [],
    [],
  )
  let new = abi_of(
    [
      {
        ..abi_function("collate_propagate_storage(bytes16)", NonPayable),
        selector: "0x42966c68",
      },
    ],
    [],
    [],
  )
  inspect(
    abi_report(old, new),
    content=(
      #|info[abi.function.added] abi.functions: function "collate_propagate_storage(bytes16)" was added to the new ABI (new: collate_propagate_storage(bytes16))
      #|error[abi.function.removed] abi.functions: function "burn(uint256)" is missing from the new ABI (old: burn(uint256))
      #|error[abi.signature.collision] abi.functions: function selector 0x42966c68 is used by "burn(uint256)" in the old ABI and "collate_propagate_storage(bytes16)" in the new ABI (old: burn(uint256), new: collate_propagate_storage(bytes16))
      #|
    ),
  )
  assert_true(
    @moonupgradeguard.blocks_upgrade(@moonupgradeguard.compare_abi(old, new)),
  )
}

///|
test "a topic handed to another event signature is an error" {
  let old = abi_of([], [{ ..abi_event("A(uint256)"), topic: "0xsame", }], [])
  let new = abi_of([], [{ ..abi_event("B(bytes16)"), topic: "0xsame", }], [])
  inspect(
    abi_report(old, new),
    content=(
      #|info[abi.event.added] abi.events: event "B(bytes16)" was added to the new ABI (new: B(bytes16))
      #|error[abi.event.removed] abi.events: event "A(uint256)" is missing from the new ABI (old: A(uint256))
      #|error[abi.signature.collision] abi.events: event topic 0xsame is used by "A(uint256)" in the old ABI and "B(bytes16)" in the new ABI (old: A(uint256), new: B(bytes16))
      #|
    ),
  )
  assert_true(
    @moonupgradeguard.blocks_upgrade(@moonupgradeguard.compare_abi(old, new)),
  )
}

///|
test "an anonymous event cannot take over a topic" {
  let old = abi_of(
    [],
    [{ ..abi_event("A(uint256)"), topic: "0xsame", anonymous: true, }],
    [],
  )
  let new = abi_of([], [{ ..abi_event("B(bytes16)"), topic: "0xsame", }], [])
  let diagnostics = @moonupgradeguard.compare_abi(old, new)
  // The event was still removed and another added, which is reported, but the
  // anonymous one never held the topic, so no collision is reported.
  let mut collisions = 0
  for diagnostic in diagnostics {
    if diagnostic.code ==
      @moonupgradeguard.DiagnosticCode::AbiSignatureCollision {
      collisions += 1
    }
  }
  assert_eq(collisions, 0)
  inspect(
    @moonupgradeguard.render_text(diagnostics),
    content=(
      #|info[abi.event.added] abi.events: event "B(bytes16)" was added to the new ABI (new: B(bytes16))
      #|error[abi.event.removed] abi.events: event "A(uint256)" is missing from the new ABI (old: A(uint256))
      #|
    ),
  )
}
