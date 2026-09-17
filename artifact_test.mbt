///| Black-box tests for artifact extraction.
///
/// Every fixture is written for these tests, following the shapes documented
/// by the writers they describe: the Solidity compiler's `storageLayout` and
/// Standard JSON output, the Foundry artifact, and the Hardhat artifact and
/// build info formats.

///|
/// A layout with one `uint256` variable at slot 0.
let layout_a : String =
  #|{"storage":[{"astId":1,"contract":"fileA:A","label":"x","offset":0,"slot":"0","type":"t_uint256"}],"types":{"t_uint256":{"encoding":"inplace","label":"uint256","numberOfBytes":"32"}}}

///|
/// A second layout, so that a wrapper can hold an ambiguous pair.
let layout_b : String =
  #|{"storage":[{"astId":2,"contract":"fileA:B","label":"y","offset":0,"slot":"1","type":"t_bool"}],"types":{"t_bool":{"encoding":"inplace","label":"bool","numberOfBytes":"1"}}}

///|
fn flat_artifact(layout : String) -> String {
  "{\"abi\":[],\"bytecode\":{\"object\":\"0x\"},\"storageLayout\":" +
  layout +
  "}"
}

///|
fn contract_object(layout : String) -> String {
  "{\"abi\":[],\"storageLayout\":" + layout + "}"
}

///|
fn standard_json(contracts : String) -> String {
  "{\"contracts\":" + contracts + "}"
}

///|
/// Extracts an artifact that is expected to succeed.
fn extracted(text : String) -> @moonupgradeguard.Artifact raise {
  let (artifact, diagnostics) = @moonupgradeguard.extract_artifact(text)
  assert_eq(
    diagnostics.length(),
    0,
    msg="unexpected diagnostics:\n\{@moonupgradeguard.render_text(diagnostics)}",
  )
  match artifact {
    Some(artifact) => artifact
    None => abort("extraction produced no artifact")
  }
}

///|
/// Extracts an artifact that is expected to fail, and renders why.
fn failure(text : String) -> String raise {
  let (artifact, diagnostics) = @moonupgradeguard.extract_artifact(text)
  assert_true(artifact is None)
  assert_true(diagnostics.length() > 0)
  @moonupgradeguard.render_text(diagnostics)
}

///|
test "every wrapper shape yields the same core model" {
  let raw = extracted(layout_a)
  assert_eq(raw.kind, @moonupgradeguard.ArtifactKind::Layout)
  assert_eq(raw.source, None)
  assert_eq(raw.contract, None)
  let flat = extracted(flat_artifact(layout_a))
  assert_eq(flat.kind, @moonupgradeguard.ArtifactKind::FlatArtifact)
  let standard = extracted(
    standard_json("{\"fileA.sol\":{\"A\":" + contract_object(layout_a) + "}}"),
  )
  assert_eq(standard.kind, @moonupgradeguard.ArtifactKind::StandardJson)
  let build_info = extracted(
    "{\"solcVersion\":\"0.8.28\",\"output\":" +
    standard_json("{\"fileA.sol\":{\"A\":" + contract_object(layout_a) + "}}") +
    "}",
  )
  assert_eq(build_info.kind, @moonupgradeguard.ArtifactKind::BuildInfo)
  assert_eq(flat.layout, raw.layout)
  assert_eq(standard.layout, raw.layout)
  assert_eq(build_info.layout, raw.layout)
  // The extracted layout feeds normalization directly.
  let (layout, diagnostics) = @moonupgradeguard.normalize_layout(raw.layout)
  assert_eq(diagnostics.length(), 0)
  assert_eq(layout.entries.length(), 1)
  assert_eq(layout.entries[0].label, "x")
  assert_eq(layout.entries[0].slot.to_string(), "0")
}

///|
test "a raw layout keeps its storage entries and types" {
  let artifact = extracted(layout_a)
  assert_eq(artifact.layout.storage.length(), 1)
  assert_eq(artifact.layout.types.length(), 1)
  assert_eq(artifact.layout.storage[0].label, Some("x"))
  assert_eq(artifact.layout.storage[0].offset, Some(0))
  assert_eq(artifact.layout.storage[0].type_id, Some("t_uint256"))
  assert_eq(artifact.layout.types[0].id, Some("t_uint256"))
  assert_eq(artifact.layout.types[0].number_of_bytes, Some("32"))
}

///|
test "a flat artifact records the names it carries" {
  let artifact = extracted(
    "{\"contractName\":\"Vault\",\"sourceName\":\"contracts/Vault.sol\",\"abi\":[],\"storageLayout\":" +
    layout_a +
    "}",
  )
  assert_eq(artifact.kind, @moonupgradeguard.ArtifactKind::FlatArtifact)
  assert_eq(artifact.contract, Some("Vault"))
  assert_eq(artifact.source, Some("contracts/Vault.sol"))
}

///|
test "Standard JSON output records its source and contract keys" {
  let artifact = extracted(
    standard_json(
      "{\"src/Vault.sol\":{\"Vault\":" + contract_object(layout_a) + "}}",
    ),
  )
  assert_eq(artifact.source, Some("src/Vault.sol"))
  assert_eq(artifact.contract, Some("Vault"))
}

///|
test "the type table is sorted so key order cannot leak through" {
  let text =
    #|{"storage":[],"types":{"t_uint256":{"encoding":"inplace","label":"uint256","numberOfBytes":"32"},"t_bool":{"encoding":"inplace","label":"bool","numberOfBytes":"1"},"t_uint128":{"encoding":"inplace","label":"uint128","numberOfBytes":"16"}}}
  let artifact = extracted(text)
  let ids : Array[String] = []
  for entry in artifact.layout.types {
    match entry.id {
      Some(id) => ids.push(id)
      None => abort("a decoded type has no id")
    }
  }
  assert_eq(ids, ["t_bool", "t_uint128", "t_uint256"])
}

///|
test "types may be null or absent" {
  let null_types = extracted("{\"storage\":[],\"types\":null}")
  assert_eq(null_types.layout.types.length(), 0)
  let absent_types = extracted("{\"storage\":[]}")
  assert_eq(absent_types.layout.types.length(), 0)
}

///|
test "two layouts without a selector are ambiguous" {
  inspect(
    failure(
      standard_json(
        "{\"fileA.sol\":{\"A\":" +
        contract_object(layout_a) +
        ",\"B\":" +
        contract_object(layout_b) +
        "}}",
      ),
    ),
    content=(
      #|error[artifact.contract.ambiguous] $.contracts: artifact holds 2 storage layouts; select one of $.contracts["fileA.sol"]["A"], $.contracts["fileA.sol"]["B"]
      #|
    ),
  )
}

///|
test "a selector picks one of several layouts" {
  let text = standard_json(
    "{\"fileA.sol\":{\"A\":" +
    contract_object(layout_a) +
    ",\"B\":" +
    contract_object(layout_b) +
    "}}",
  )
  let (artifact, diagnostics) = @moonupgradeguard.extract_artifact(
    text,
    select="B",
  )
  assert_eq(diagnostics.length(), 0)
  match artifact {
    Some(artifact) => {
      assert_eq(artifact.contract, Some("B"))
      assert_eq(artifact.layout.storage[0].label, Some("y"))
    }
    None => abort("extraction produced no artifact")
  }
}

///|
test "a selector may qualify the source" {
  let text = standard_json(
    "{\"fileA.sol\":{\"A\":" +
    contract_object(layout_a) +
    "},\"fileB.sol\":{\"A\":" +
    contract_object(layout_b) +
    "}}",
  )
  let (artifact, diagnostics) = @moonupgradeguard.extract_artifact(
    text,
    select="fileB.sol:A",
  )
  assert_eq(diagnostics.length(), 0)
  match artifact {
    Some(artifact) => {
      assert_eq(artifact.source, Some("fileB.sol"))
      assert_eq(artifact.layout.storage[0].label, Some("y"))
    }
    None => abort("extraction produced no artifact")
  }
}

///|
test "a selector that matches nothing is reported with the alternatives" {
  let text = standard_json(
    "{\"fileA.sol\":{\"A\":" + contract_object(layout_a) + "}}",
  )
  let (artifact, diagnostics) = @moonupgradeguard.extract_artifact(
    text,
    select="Vault",
  )
  assert_true(artifact is None)
  inspect(
    @moonupgradeguard.render_text(diagnostics),
    content=(
      #|error[artifact.contract.missing] $.contracts: no storage layout matches "Vault"; available: $.contracts["fileA.sol"]["A"]
      #|
    ),
  )
}

///|
test "a Hardhat artifact reports that it carries no layout" {
  inspect(
    failure(
      "{\"_format\":\"hh-sol-artifact-1\",\"contractName\":\"Vault\",\"sourceName\":\"contracts/Vault.sol\",\"abi\":[],\"bytecode\":\"0x6080\",\"deployedBytecode\":\"0x6080\"}",
    ),
    content=(
      #|error[artifact.layout.missing] $: artifact of format "hh-sol-artifact-1" does not contain a storage layout; compile with the storageLayout output selected
      #|
    ),
  )
}

///|
test "compiler output without a storage layout says which setting is missing" {
  inspect(
    failure(standard_json("{\"fileA.sol\":{\"A\":{\"abi\":[]}}}")),
    content=(
      #|error[artifact.layout.missing] $.contracts: compiler output contains no storage layout; compile with the storageLayout output selected
      #|
    ),
  )
}

///|
test "invalid JSON is reported" {
  inspect(
    failure("{\"storage\": ["),
    content=(
      #|error[artifact.json.invalid] $: artifact is not valid JSON: Unexpected end of file
      #|
    ),
  )
}

///|
test "a root that is not an object is reported" {
  inspect(
    failure("[1, 2]"),
    content=(
      #|error[artifact.shape.unsupported] $: artifact root must be a JSON object
      #|
    ),
  )
}

///|
test "an object that is no known shape is reported" {
  inspect(
    failure("{\"hello\":\"world\"}"),
    content=(
      #|error[artifact.shape.unsupported] $: artifact is not a recognized shape; expected a storage layout object, a flat artifact with storageLayout, or compiler output with contracts
      #|
    ),
  )
}

///|
test "compiler input is reported as carrying no layout" {
  inspect(
    failure(
      "{\"language\":\"Solidity\",\"sources\":{\"a.sol\":{\"content\":\"contract A {}\"}}}",
    ),
    content=(
      #|error[artifact.shape.unsupported] $: artifact is compiler input, which carries no storage layout; pass compiler output or a compile artifact
      #|
    ),
  )
}

///|
test "an artifact that matches two shapes is ambiguous" {
  inspect(
    failure("{\"contracts\":{},\"storageLayout\":" + layout_a + "}"),
    content=(
      #|error[artifact.shape.ambiguous] $: artifact matches more than one known shape (a flat artifact, Standard JSON output); extract one artifact shape at a time
      #|
    ),
  )
}

///|
test "a field of the wrong JSON type is reported where it sits" {
  inspect(
    failure(
      "{\"storage\":[{\"label\":\"x\",\"slot\":0,\"offset\":0,\"type\":\"t_uint256\"}],\"types\":{}}",
    ),
    content=(
      #|error[artifact.field.invalid] $.storage[0].slot: expected a JSON string
      #|
    ),
  )
}

///|
test "diagnostics from one document come out sorted" {
  inspect(
    failure(
      "{\"contracts\":{\"b.sol\":{\"Z\":{\"storageLayout\":\"nope\"}},\"a.sol\":{\"A\":{\"storageLayout\":\"nope\"}}}}",
    ),
    content=(
      #|error[artifact.layout.missing] $.contracts: compiler output contains no storage layout; compile with the storageLayout output selected
      #|error[artifact.field.invalid] $.contracts["a.sol"]["A"].storageLayout: expected a JSON object
      #|error[artifact.field.invalid] $.contracts["b.sol"]["Z"].storageLayout: expected a JSON object
      #|
    ),
  )
}

///|
test "a storage entry that is not an object is reported" {
  inspect(
    failure("{\"storage\":[1],\"types\":{}}"),
    content=(
      #|error[artifact.field.invalid] $.storage[0]: expected a JSON object
      #|
    ),
  )
}

///|
test "a layout without a storage array is reported" {
  inspect(
    failure("{\"types\":{}}"),
    content=(
      #|error[artifact.field.invalid] $.storage: required field is missing
      #|
    ),
  )
}

///|
test "transient storage is reported as informational" {
  let text =
    #|{"abi":[],"storageLayout":{"storage":[{"astId":1,"contract":"fileA:A","label":"x","offset":0,"slot":"0","type":"t_uint256"}],"types":{"t_uint256":{"encoding":"inplace","label":"uint256","numberOfBytes":"32"}}},"transientStorageLayout":{"storage":[{"astId":5,"contract":"fileA:A","label":"t","offset":0,"slot":"0","type":"t_uint256"}],"types":{"t_uint256":{"encoding":"inplace","label":"uint256","numberOfBytes":"32"}}}}
  let (artifact, diagnostics) = @moonupgradeguard.extract_artifact(text)
  assert_true(artifact is Some(_))
  assert_eq(diagnostics.length(), 1)
  assert_eq(
    diagnostics[0].code,
    @moonupgradeguard.DiagnosticCode::ArtifactTransientStoragePresent,
  )
  assert_eq(diagnostics[0].severity, @moonupgradeguard.Severity::Info)
  inspect(
    @moonupgradeguard.render_text(diagnostics),
    content=(
      #|info[artifact.transient-storage.present] $.transientStorageLayout: contract has transient storage variables; this version compares regular storage only
      #|
    ),
  )
}
