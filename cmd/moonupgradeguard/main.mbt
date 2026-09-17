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
}

///|
priv struct CliResult {
  output : String
  exit_code : Int
}

///|
let usage =
  #|usage: moonupgradeguard <check|storage|abi> OLD NEW [--format text|json]

///|
async fn main {
  let args = @env.args()
  if args.length() == 2 && (args[1] == "--help" || args[1] == "-h") {
    emit(usage)
    process_exit(0)
    return
  }
  let options = match parse_args(args) {
    Ok(options) => options
    Err(message) => {
      println(message)
      emit(usage)
      process_exit(2)
      return
    }
  }
  let old_text = read_input(options.old_path)
  let new_text = read_input(options.new_path)
  let result = analyze_text(options.command, old_text, new_text, options.format)
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
  if args.length() != 4 && args.length() != 6 {
    return Err("moonupgradeguard: expected a command and two artifact paths")
  }
  let command = match args[1] {
    "check" => Check
    "storage" => Storage
    "abi" => Abi
    other => return Err("moonupgradeguard: unknown command \"\{other}\"")
  }
  let format = if args.length() == 4 {
    Text
  } else {
    if args[4] != "--format" {
      return Err("moonupgradeguard: expected --format text|json")
    }
    match args[5] {
      "text" => Text
      "json" => Json
      other => return Err("moonupgradeguard: unknown format \"\{other}\"")
    }
  }
  Ok({ command, old_path: args[2], new_path: args[3], format, })
}

///|
async fn read_input(path : String) -> String {
  @fs.read_file(path).text() catch {
    error => {
      println("moonupgradeguard: cannot read \"\{path}\": \{error}")
      process_exit(2)
      abort("unreachable")
    }
  }
}

///|
fn analyze_text(
  command : Command,
  old_text : String,
  new_text : String,
  format : OutputFormat,
) -> CliResult {
  let diagnostics : Array[@guard.Diagnostic] = []
  let (old_artifact, old_extract) = @guard.extract_artifact(old_text)
  let (new_artifact, new_extract) = @guard.extract_artifact(new_text)
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
  append_diagnostics(diagnostics, old_normalize)
  append_diagnostics(diagnostics, new_normalize)
  if has_errors(diagnostics) {
    return finish(diagnostics, format, 2)
  }
  if command == Check || command == Storage {
    append_diagnostics(
      diagnostics,
      @guard.compare_storage(old_layout, new_layout),
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
