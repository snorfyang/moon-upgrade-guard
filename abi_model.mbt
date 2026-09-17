///| Backend-independent ABI model.
///
/// Compiler ABIs are normalized so that comparison works on canonical
/// signatures and selectors, and so that JSON key order, parameter names, and
/// compiler-generated ids cannot influence the result.

///|
/// Kind of callable ABI entry.
pub(all) enum AbiEntryKind {
  /// A named function.
  Function
  /// The `fallback` entry.
  Fallback
  /// The `receive` entry.
  Receive
} derive(Eq, @debug.Debug)

///|
/// State mutability of a callable entry.
pub(all) enum Mutability {
  /// Declared `pure`.
  Pure
  /// Declared `view`.
  View
  /// Declared without a mutability keyword.
  NonPayable
  /// Declared `payable`.
  Payable
} derive(Eq, @debug.Debug)

///|
/// Name of the mutability, as the compiler writes it in the ABI.
pub fn Mutability::name(self : Mutability) -> String {
  match self {
    Pure => "pure"
    View => "view"
    NonPayable => "nonpayable"
    Payable => "payable"
  }
}

///|
/// One ABI parameter.
pub(all) struct AbiParam {
  /// Declared name. Not part of the canonical signature.
  name : String
  /// Canonical type name, such as `uint256` or `(uint256,address)[]`.
  type_name : String
  /// Whether an event parameter is indexed. False everywhere else.
  indexed : Bool
} derive(Eq, @debug.Debug)

///|
/// A normalized callable entry: a function, a fallback, or a receive entry.
pub(all) struct AbiFunction {
  /// Which callable this is.
  kind : AbiEntryKind
  /// Function name, empty for fallback and receive.
  name : String
  /// Canonical signature, such as `transfer(address,uint256)`, or
  /// `fallback()` and `receive()`.
  signature : String
  /// Four-byte selector as `0x` plus eight lowercase hex digits. It is always
  /// the hash of the signature; fallback and receive are not dispatched by
  /// selector, so their value is informational.
  selector : String
  /// Input parameters, in declaration order.
  inputs : Array[AbiParam]
  /// Output parameters, in declaration order. Always empty for fallback and
  /// receive.
  outputs : Array[AbiParam]
  /// State mutability.
  mutability : Mutability
} derive(Eq, @debug.Debug)

///|
/// A normalized event.
pub(all) struct AbiEvent {
  /// Event name.
  name : String
  /// Canonical signature. The topic is the hash of this string.
  signature : String
  /// 32-byte topic, as `0x` plus 64 lowercase hex digits.
  topic : String
  /// Input parameters, in declaration order.
  inputs : Array[AbiParam]
  /// Whether the event is declared `anonymous`, which removes the topic.
  anonymous : Bool
} derive(Eq, @debug.Debug)

///|
/// A normalized custom error.
pub(all) struct AbiError {
  /// Error name.
  name : String
  /// Canonical signature.
  signature : String
  /// Four-byte selector as `0x` plus eight lowercase hex digits. It is always
  /// the hash of the signature; fallback and receive are not dispatched by
  /// selector, so their value is informational.
  selector : String
  /// Input parameters, in declaration order.
  inputs : Array[AbiParam]
} derive(Eq, @debug.Debug)

///|
/// A normalized contract ABI.
pub(all) struct Abi {
  /// Callable entries, in artifact order.
  functions : Array[AbiFunction]
  /// Events, in artifact order.
  events : Array[AbiEvent]
  /// Custom errors, in artifact order.
  errors : Array[AbiError]
} derive(Eq, @debug.Debug)

///|
/// The empty ABI, as a contract without callable entries has.
pub fn Abi::empty() -> Abi {
  { functions: [], events: [], errors: [], }
}
