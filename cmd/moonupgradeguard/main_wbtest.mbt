///|
let empty_layout =
  #|{"storage":[],"types":{}}

///|
let layout_with_abi =
  #|{"storageLayout":{"storage":[],"types":{}},"abi":[]}

///|
test "arguments select a command and output format" {
  let parsed = parse_args([
    "moonupgradeguard", "abi", "old.json", "new.json", "--format", "json",
  ])
  match parsed {
    Ok(options) => {
      assert_true(options.command == Abi)
      assert_eq(options.old_path, "old.json")
      assert_eq(options.new_path, "new.json")
      assert_true(options.format is Json)
    }
    Err(message) => fail(message)
  }
  assert_true(
    parse_args(["moonupgradeguard", "bad", "old.json", "new.json"]) is Err(_),
  )
}

///|
test "unchanged standalone layouts pass check" {
  let result = analyze_text(Check, empty_layout, empty_layout, Text)
  assert_eq(result.exit_code, 0)
  assert_eq(result.output, "")
}

///|
test "invalid input uses exit code two" {
  let result = analyze_text(Check, "not json", empty_layout, Text)
  assert_eq(result.exit_code, 2)
  assert_true(result.output.contains("artifact.json.invalid"))
}

///|
test "abi command requires both artifacts to carry an ABI" {
  let result = analyze_text(Abi, empty_layout, layout_with_abi, Json)
  assert_eq(result.exit_code, 2)
  assert_true(result.output.contains("artifact.abi.missing"))
}

///|
test "storage incompatibility uses exit code one" {
  let old =
    #|{"storage":[{"contract":"A","label":"x","offset":0,"slot":"0","type":"t_uint256"}],"types":{"t_uint256":{"encoding":"inplace","label":"uint256","numberOfBytes":"32"}}}
  let new =
    #|{"storage":[],"types":{}}
  let result = analyze_text(Storage, old, new, Text)
  assert_eq(result.exit_code, 1)
  assert_true(result.output.contains("storage.entry.removed"))
}

///|
test "the output format is read before the arguments are validated" {
  assert_true(wants_json(["moonupgradeguard", "bad", "--format", "json"]))
  assert_true(!wants_json(["moonupgradeguard", "check", "a.json", "b.json"]))
  assert_true(
    !wants_json([
      "moonupgradeguard", "check", "a.json", "b.json", "--format", "text",
    ]),
  )
  assert_true(!wants_json(["moonupgradeguard"]))
}
