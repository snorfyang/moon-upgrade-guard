///|
/// Clean process exit for the native backend.
#cfg(any(target="native", target="llvm"))
extern "c" fn process_exit(code : Int) = "exit"

///|
priv enum Command {
  Check
  Storage
  Abi
} derive(Eq)

///|
priv enum OutputFormat {
  Text
  Json
}

///|
priv struct Options {
  command : Command
  old_path : String
  new_path : String
  format : OutputFormat
  contract : String?
}

///|
priv struct CliResult {
  output : String
  exit_code : Int
}

///|
let usage =
  #|usage: moonupgradeguard <check|storage|abi> OLD NEW [--format text|json]
  #|       [--contract NAME|SOURCE:NAME]
  #|       moonupgradeguard --version

///|
async fn main {
  let args = @env.args()
  if args.length() == 2 && (args[1] == "--help" || args[1] == "-h") {
    emit(usage)
    process_exit(0)
    return
  }
  if args.length() == 2 && args[1] == "--version" {
    emit("moonupgradeguard \{@guard.version}")
    process_exit(0)
    return
  }
  // The format is read before the arguments are validated, so that a failure
  // can still answer in the format the caller asked for.
  let json = wants_json(args)
  let options = match parse_args(args) {
    Ok(options) => options
    Err(message) =>
      fail_operational(
        @guard.DiagnosticCode::CliArgumentInvalid,
        { contract: None, path: "$", },
        message,
        json,
        true,
      )
  }
  let old_text = read_input(options.old_path, json)
  let new_text = read_input(options.new_path, json)
  let result = analyze_text(
    options.command,
    old_text,
    new_text,
    options.format,
    options.contract,
  )
  if !result.output.is_empty() {
    emit(result.output)
  }
  process_exit(result.exit_code)
}

///|
fn emit(value : String) -> Unit {
  if value.has_suffix("\n") {
    println(value[:value.length() - 1])
  } else {
    println(value)
  }
}

///|
fn parse_args(args : Array[String]) -> Result[Options, String] {
  if args.length() < 4 {
    return Err("expected a command and two artifact paths")
  }
  let command = match args[1] {
    "check" => Check
    "storage" => Storage
    "abi" => Abi
    other => return Err("unknown command \"\{other}\"")
  }
  let mut format = Text
  let mut contract : String? = None
  let mut i = 4
  while i < args.length() {
    match args[i] {
      "--format" => {
        if i + 1 >= args.length() {
          return Err("--format needs text or json")
        }
        format = match args[i + 1] {
          "text" => Text
          "json" => Json
          other => return Err("unknown format \"\{other}\"")
        }
        i += 2
      }
      "--contract" => {
        if i + 1 >= args.length() {
          return Err("--contract needs a contract name or source:contract")
        }
        contract = Some(args[i + 1])
        i += 2
      }
      other => return Err("unknown option \"\{other}\"")
    }
  }
  Ok({ command, old_path: args[2], new_path: args[3], format, contract, })
}

///|
/// Whether the arguments ask for JSON output.
fn wants_json(args : Array[String]) -> Bool {
  if args.length() < 2 {
    return false
  }
  for i in 0..<(args.length() - 1) {
    if args[i] == "--format" && args[i + 1] == "json" {
      return true
    }
  }
  false
}

///|
/// Reports an operational failure and exits.
///
/// With `--format json`, stdout is a JSON array of findings on every exit code,
/// so a failure that never reached the analysis reports itself as a finding
/// rather than as prose that a JSON reader cannot parse. In text mode the
/// finding is followed by the usage line when the command line was at fault.
fn[T] fail_operational(
  code : @guard.DiagnosticCode,
  location : @guard.Location,
  message : String,
  json : Bool,
  show_usage : Bool,
) -> T {
  let diagnostic = @guard.Diagnostic::new(code, location, message)
  if json {
    emit(@guard.render_json([diagnostic]))
  } else {
    emit(@guard.render_text([diagnostic]))
    if show_usage {
      emit(usage)
    }
  }
  process_exit(2)
  abort("unreachable")
}

///|
async fn read_input(path : String, json : Bool) -> String {
  @fs.read_file(path).text() catch {
    error =>
      fail_operational(
        @guard.DiagnosticCode::CliInputUnreadable,
        { contract: None, path, },
        "cannot read \"\{path}\": \{error}",
        json,
        false,
      )
  }
}

///|
/// Extracts an artifact, selecting a contract when the caller named one.
///
/// Wrappers that hold several contracts need the selector; the library reports
/// an ambiguity rather than guessing when it is missing.
fn extract(
  text : String,
  contract : String?,
) -> (@guard.Artifact?, Array[@guard.Diagnostic]) {
  match contract {
    Some(name) => @guard.extract_artifact(text, select=name)
    None => @guard.extract_artifact(text)
  }
}

///|
/// Normalizes a transient storage layout.
///
/// An artifact that reports no transient layout is treated as one with no
/// transient variables, which is how Foundry writes an empty one. A variable
/// that disappears because of that is reported as a removal, so the run blocks
/// rather than passing silently.
fn normalize_transient(
  raw : @guard.RawStorageLayout?,
) -> (@guard.StorageLayout, Array[@guard.Diagnostic]) {
  match raw {
    Some(raw) => @guard.normalize_layout(raw, prefix="transientStorage.")
    None => (@guard.StorageLayout::empty(), [])
  }
}

///|
fn analyze_text(
  command : Command,
  old_text : String,
  new_text : String,
  format : OutputFormat,
  contract : String?,
) -> CliResult {
  let diagnostics : Array[@guard.Diagnostic] = []
  let (old_artifact, old_extract) = extract(old_text, contract)
  let (new_artifact, new_extract) = extract(new_text, contract)
  append_diagnostics(diagnostics, old_extract)
  append_diagnostics(diagnostics, new_extract)
  if has_errors(diagnostics) || old_artifact is None || new_artifact is None {
    return finish(diagnostics, format, 2)
  }
  guard old_artifact is Some(old_artifact) else {
    return finish(diagnostics, format, 2)
  }
  guard new_artifact is Some(new_artifact) else {
    return finish(diagnostics, format, 2)
  }
  let (old_layout, old_normalize) = @guard.normalize_layout(old_artifact.layout)
  let (new_layout, new_normalize) = @guard.normalize_layout(new_artifact.layout)
  let (old_transient, old_transient_normalize) = normalize_transient(
    old_artifact.transient,
  )
  let (new_transient, new_transient_normalize) = normalize_transient(
    new_artifact.transient,
  )
  append_diagnostics(diagnostics, old_normalize)
  append_diagnostics(diagnostics, new_normalize)
  append_diagnostics(diagnostics, old_transient_normalize)
  append_diagnostics(diagnostics, new_transient_normalize)
  if has_errors(diagnostics) {
    return finish(diagnostics, format, 2)
  }
  if command == Check || command == Storage {
    append_diagnostics(
      diagnostics,
      @guard.compare_storage(old_layout, new_layout),
    )
    append_diagnostics(
      diagnostics,
      @guard.compare_transient(old_transient, new_transient),
    )
  }
  if command == Check || command == Abi {
    match (old_artifact.abi, new_artifact.abi) {
      (Some(old_abi), Some(new_abi)) =>
        append_diagnostics(diagnostics, @guard.compare_abi(old_abi, new_abi))
      (None, None) =>
        if command == Abi {
          diagnostics.push(missing_abi("old and new artifacts", None))
        }
      (None, Some(_)) =>
        diagnostics.push(missing_abi("old artifact", old_artifact.contract))
      (Some(_), None) =>
        diagnostics.push(missing_abi("new artifact", new_artifact.contract))
    }
  }
  let exit_code = if has_missing_abi(diagnostics) {
    2
  } else if @guard.blocks_upgrade(diagnostics) {
    1
  } else {
    0
  }
  finish(diagnostics, format, exit_code)
}

///|
fn missing_abi(subject : String, contract : String?) -> @guard.Diagnostic {
  @guard.Diagnostic::new(
    @guard.DiagnosticCode::ArtifactAbiMissing,
    { contract, path: "abi", },
    "\{subject} does not contain an ABI required by this command",
  )
}

///|
fn append_diagnostics(
  target : Array[@guard.Diagnostic],
  source : Array[@guard.Diagnostic],
) -> Unit {
  for diagnostic in source {
    target.push(diagnostic)
  }
}

///|
fn has_errors(diagnostics : Array[@guard.Diagnostic]) -> Bool {
  for diagnostic in diagnostics {
    if diagnostic.severity == @guard.Severity::Error {
      return true
    }
  }
  false
}

///|
fn has_missing_abi(diagnostics : Array[@guard.Diagnostic]) -> Bool {
  for diagnostic in diagnostics {
    if diagnostic.code == @guard.DiagnosticCode::ArtifactAbiMissing {
      return true
    }
  }
  false
}

///|
fn finish(
  diagnostics : Array[@guard.Diagnostic],
  format : OutputFormat,
  exit_code : Int,
) -> CliResult {
  let output = match format {
    Text => @guard.render_text(diagnostics)
    Json => @guard.render_json(diagnostics)
  }
  { output, exit_code, }
}
