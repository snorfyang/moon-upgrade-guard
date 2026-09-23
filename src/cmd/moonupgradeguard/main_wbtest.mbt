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
  let result = analyze_text(Check, empty_layout, empty_layout, Text, None)
  assert_eq(result.exit_code, 0)
  assert_eq(result.output, "")
}

///|
test "invalid input uses exit code two" {
  let result = analyze_text(Check, "not json", empty_layout, Text, None)
  assert_eq(result.exit_code, 2)
  assert_true(result.output.contains("artifact.json.invalid"))
}

///|
test "both invalid artifacts identify their input" {
  let result = analyze_text(Check, "{", "{", Json, None)
  assert_eq(result.exit_code, 2)
  inspect(
    result.output,
    content=(
      #|[
      #|  {
      #|    "code": "artifact.json.invalid",
      #|    "severity": "error",
      #|    "input": "old",
      #|    "location": {"path": "$"},
      #|    "message": "artifact is not valid JSON: Unexpected end of file"
      #|  },
      #|  {
      #|    "code": "artifact.json.invalid",
      #|    "severity": "error",
      #|    "input": "new",
      #|    "location": {"path": "$"},
      #|    "message": "artifact is not valid JSON: Unexpected end of file"
      #|  }
      #|]
      #|
    ),
  )
}

///|
test "abi command requires both artifacts to carry an ABI" {
  let result = analyze_text(Abi, empty_layout, layout_with_abi, Json, None)
  assert_eq(result.exit_code, 2)
  assert_true(result.output.contains("artifact.abi.missing"))
  assert_true(result.output.contains("\"input\": \"old\""))
}

///|
test "abi command identifies both missing inputs" {
  let result = analyze_text(Abi, empty_layout, empty_layout, Json, None)
  assert_eq(result.exit_code, 2)
  assert_true(result.output.contains("\"input\": \"old\""))
  assert_true(result.output.contains("\"input\": \"new\""))
}

///|
test "storage incompatibility uses exit code one" {
  let old =
    #|{"storage":[{"contract":"A","label":"x","offset":0,"slot":"0","type":"t_uint256"}],"types":{"t_uint256":{"encoding":"inplace","label":"uint256","numberOfBytes":"32"}}}
  let new =
    #|{"storage":[],"types":{}}
  let result = analyze_text(Storage, old, new, Text, None)
  assert_eq(result.exit_code, 1)
  assert_true(result.output.contains("storage.entry.removed"))
  let json = analyze_text(Storage, old, new, Json, None)
  assert_true(!json.output.contains("\"input\""))
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

///|
test "options may appear in any order and the selector is optional" {
  let parsed = parse_args([
    "moonupgradeguard", "check", "old.json", "new.json", "--contract", "Token",
  ])
  match parsed {
    Ok(options) => assert_eq(options.contract, Some("Token"))
    Err(message) => fail(message)
  }
  let both = parse_args([
    "moonupgradeguard", "check", "old.json", "new.json", "--contract", "src/Token.sol:Token",
    "--format", "json",
  ])
  match both {
    Ok(options) => {
      assert_eq(options.contract, Some("src/Token.sol:Token"))
      assert_true(options.format is Json)
    }
    Err(message) => fail(message)
  }
  let reordered = parse_args([
    "moonupgradeguard", "storage", "old.json", "new.json", "--format", "text", "--contract",
    "Token",
  ])
  match reordered {
    Ok(options) => assert_eq(options.contract, Some("Token"))
    Err(message) => fail(message)
  }
  assert_true(
    parse_args([
      "moonupgradeguard", "check", "old.json", "new.json", "--contract",
    ])
    is Err(_),
  )
  assert_true(
    parse_args([
      "moonupgradeguard", "check", "old.json", "new.json", "--verbose",
    ])
    is Err(_),
  )
}
