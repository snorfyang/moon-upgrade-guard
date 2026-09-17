///| ABI compatibility engine.
///
/// The engine answers one question: can callers that used the old contract keep
/// using the new one through the same interface? It compares canonical
/// signatures and selectors, so renaming a parameter, reordering JSON keys, or
/// recompiling changes nothing, while changing a parameter type does, because
/// the selector changes.
///
/// Severity follows the caller, not the source:
///
/// - `Error`, because a caller breaks: a signature that disappeared from any
///   category; a function whose output types changed, because callers decode
///   return data positionally; an event whose indexed parameters changed,
///   because topic filters no longer select the same logs; an event that became
///   or stopped being anonymous, because its topic disappears or appears; and a
///   selector or topic that now belongs to a different signature. Losing
///   payability or the static-call guarantee is also an error.
/// - `Warning`, because the interface still resolves but its contract changed:
///   a non-breaking function state-mutability change. The selector and calldata
///   are unchanged, so this remains a behavioural change for review.
/// - `Info`, because the change is additive: a new function, event, or error.
///
/// Constructors are not compared: their inputs affect deployment, not the
/// interface an existing proxy exposes. A fallback or receive entry is compared
/// like a function without parameters, so removing one is an error.
///
/// One invariant comes from the compiler rather than from this engine: a
/// selector is unique within one ABI, because the compiler rejects two
/// functions that would share one. The engine therefore checks discriminators
/// across the two versions, which is where a collision can actually appear,
/// and not within one ABI.

///|
/// Compares two normalized ABIs.
///
/// Returns the diagnostics that describe the change, sorted. An empty result
/// means every old signature, output list, indexed layout, and discriminator
/// survived unchanged.
pub fn compare_abi(old : Abi, new : Abi) -> Array[Diagnostic] {
  let diagnostics : Array[Diagnostic] = []
  compare_functions(old.functions, new.functions, diagnostics)
  compare_events(old.events, new.events, diagnostics)
  compare_errors(old.errors, new.errors, diagnostics)
  compare_collisions(old, new, diagnostics)
  diagnostics.sort()
  diagnostics
}

///|
/// Splits two entry lists into the entries only in the old version, only in the
/// new version, and the pairs that share a canonical signature.
///
/// Duplicate signatures are paired in input order, which is deterministic
/// because the ABI array order comes from the artifact.
fn[T] match_signatures(
  old : Array[T],
  new : Array[T],
  signature : (T) -> String,
) -> (Array[T], Array[T], Array[(T, T)]) {
  let matched_new : Array[Bool] = Array::make(new.length(), false)
  let removed : Array[T] = []
  let matched : Array[(T, T)] = []
  for old_entry in old {
    let mut found = -1
    for j in 0..<new.length() {
      if !matched_new[j] && signature(new[j]) == signature(old_entry) {
        found = j
        break
      }
    }
    if found >= 0 {
      matched_new[found] = true
      matched.push((old_entry, new[found]))
    } else {
      removed.push(old_entry)
    }
  }
  let added : Array[T] = []
  for j in 0..<new.length() {
    if !matched_new[j] {
      added.push(new[j])
    }
  }
  (removed, added, matched)
}

///|
/// Location of one ABI section.
fn abi_section_location(section : String) -> Location {
  { contract: None, path: "abi." + section, }
}

///|
/// Location of one ABI entry, named by its canonical signature.
fn abi_entry_location(section : String, signature : String) -> Location {
  { contract: None, path: "abi." + section + "[\"" + signature + "\"]", }
}

///|
/// Compares callable entries, including fallback and receive.
fn compare_functions(
  old : Array[AbiFunction],
  new : Array[AbiFunction],
  diagnostics : Array[Diagnostic],
) -> Unit {
  let (removed, added, matched) = match_signatures(old, new, fn(entry) {
    entry.signature
  })
  for entry in removed {
    diagnostics.push(
      Diagnostic::new(
        AbiFunctionRemoved,
        abi_section_location("functions"),
        "\{entry_noun(entry.kind)} \"\{entry.signature}\" is missing from the new ABI",
      ).with_values(old_value=entry.signature),
    )
  }
  for entry in added {
    diagnostics.push(
      Diagnostic::new(
        AbiFunctionAdded,
        abi_section_location("functions"),
        "\{entry_noun(entry.kind)} \"\{entry.signature}\" was added to the new ABI",
      ).with_values(new_value=entry.signature),
    )
  }
  for pair in matched {
    let (old_entry, new_entry) = pair
    let noun = entry_noun(old_entry.kind)
    let entry_path = abi_entry_location("functions", old_entry.signature).path
    if old_entry.mutability != new_entry.mutability {
      let code = if incompatible_mutability(
          old_entry.mutability,
          new_entry.mutability,
        ) {
        AbiFunctionMutabilityIncompatible
      } else {
        AbiFunctionMutabilityChanged
      }
      diagnostics.push(
        Diagnostic::new(
          code,
          { contract: None, path: entry_path + ".stateMutability", },
          "\{noun} \"\{old_entry.signature}\" changed state mutability from \"\{old_entry.mutability.name()}\" to \"\{new_entry.mutability.name()}\"",
        ).with_values(
          old_value=old_entry.mutability.name(),
          new_value=new_entry.mutability.name(),
        ),
      )
    }
    let old_outputs = output_types(old_entry)
    let new_outputs = output_types(new_entry)
    if old_outputs != new_outputs {
      diagnostics.push(
        Diagnostic::new(
          AbiFunctionOutputsChanged,
          { contract: None, path: entry_path + ".outputs", },
          "\{noun} \"\{old_entry.signature}\" changed its output types from \"\{old_outputs}\" to \"\{new_outputs}\"",
        ).with_values(old_value=old_outputs, new_value=new_outputs),
      )
    }
  }
}

///|
/// Whether a mutability change removes behavior existing callers may rely on.
/// Payable callers may send value, while callers compiled against a pure or
/// view interface use a static call that cannot execute newly permitted writes.
fn incompatible_mutability(old : Mutability, new : Mutability) -> Bool {
  match old {
    Payable => new != Payable
    Pure | View => new == NonPayable || new == Payable
    NonPayable => false
  }
}

///|
/// Compares events.
fn compare_events(
  old : Array[AbiEvent],
  new : Array[AbiEvent],
  diagnostics : Array[Diagnostic],
) -> Unit {
  let (removed, added, matched) = match_signatures(old, new, fn(entry) {
    entry.signature
  })
  for entry in removed {
    diagnostics.push(
      Diagnostic::new(
        AbiEventRemoved,
        abi_section_location("events"),
        "event \"\{entry.signature}\" is missing from the new ABI",
      ).with_values(old_value=entry.signature),
    )
  }
  for entry in added {
    diagnostics.push(
      Diagnostic::new(
        AbiEventAdded,
        abi_section_location("events"),
        "event \"\{entry.signature}\" was added to the new ABI",
      ).with_values(new_value=entry.signature),
    )
  }
  for pair in matched {
    let (old_entry, new_entry) = pair
    let entry_path = abi_entry_location("events", old_entry.signature).path
    let old_indexed = indexed_flags(old_entry)
    let new_indexed = indexed_flags(new_entry)
    if old_indexed != new_indexed {
      diagnostics.push(
        Diagnostic::new(
          AbiEventIndexedChanged,
          { contract: None, path: entry_path + ".inputs", },
          "event \"\{old_entry.signature}\" changed its indexed parameters from \"\{old_indexed}\" to \"\{new_indexed}\"",
        ).with_values(old_value=old_indexed, new_value=new_indexed),
      )
    }
    if old_entry.anonymous != new_entry.anonymous {
      diagnostics.push(
        Diagnostic::new(
          AbiEventAnonymousChanged,
          { contract: None, path: entry_path + ".anonymous", },
          "event \"\{old_entry.signature}\" changed from anonymous=\{old_entry.anonymous} to anonymous=\{new_entry.anonymous}",
        ).with_values(
          old_value=old_entry.anonymous.to_string(),
          new_value=new_entry.anonymous.to_string(),
        ),
      )
    }
  }
}

///|
/// Compares custom errors. Matching signatures have identical inputs by
/// construction, so only appearance and disappearance are reported.
fn compare_errors(
  old : Array[AbiError],
  new : Array[AbiError],
  diagnostics : Array[Diagnostic],
) -> Unit {
  let (removed, added, _) = match_signatures(old, new, fn(entry) {
    entry.signature
  })
  for entry in removed {
    diagnostics.push(
      Diagnostic::new(
        AbiErrorRemoved,
        abi_section_location("errors"),
        "error \"\{entry.signature}\" is missing from the new ABI",
      ).with_values(old_value=entry.signature),
    )
  }
  for entry in added {
    diagnostics.push(
      Diagnostic::new(
        AbiErrorAdded,
        abi_section_location("errors"),
        "error \"\{entry.signature}\" was added to the new ABI",
      ).with_values(new_value=entry.signature),
    )
  }
}

///|
/// Reports discriminators that the two versions use for different signatures.
///
/// A function selector is four bytes of call data and an event topic is the
/// hash of the event signature. When the new version hands one of them to a
/// different signature, a caller that keeps the old calldata or the old filter
/// silently reaches something else, which no per-signature comparison can see.
fn compare_collisions(
  old : Abi,
  new : Abi,
  diagnostics : Array[Diagnostic],
) -> Unit {
  // Only real functions are dispatched by selector: a fallback or receive
  // entry answers any selector that no function claims, so it cannot take one
  // over.
  let old_functions : Array[AbiFunction] = []
  for entry in old.functions {
    if entry.kind == Function {
      old_functions.push(entry)
    }
  }
  let new_functions : Array[AbiFunction] = []
  for entry in new.functions {
    if entry.kind == Function {
      new_functions.push(entry)
    }
  }
  report_collisions(
    old_functions,
    new_functions,
    fn(entry) { entry.signature },
    fn(entry) { entry.selector },
    "functions",
    "function selector",
    diagnostics,
  )
  report_collisions(
    old.errors,
    new.errors,
    fn(entry) { entry.signature },
    fn(entry) { entry.selector },
    "errors",
    "error selector",
    diagnostics,
  )
  // An anonymous event occupies no topic, so it cannot take one over.
  let old_events : Array[AbiEvent] = []
  for entry in old.events {
    if !entry.anonymous {
      old_events.push(entry)
    }
  }
  let new_events : Array[AbiEvent] = []
  for entry in new.events {
    if !entry.anonymous {
      new_events.push(entry)
    }
  }
  report_collisions(
    old_events,
    new_events,
    fn(entry) { entry.signature },
    fn(entry) { entry.topic },
    "events",
    "event topic",
    diagnostics,
  )
}

///|
/// Reports every pair of entries that shares a discriminator with a different
/// signature.
fn[T] report_collisions(
  old : Array[T],
  new : Array[T],
  signature : (T) -> String,
  discriminator : (T) -> String,
  section : String,
  noun : String,
  diagnostics : Array[Diagnostic],
) -> Unit {
  for old_entry in old {
    for new_entry in new {
      if discriminator(old_entry) == discriminator(new_entry) &&
        signature(old_entry) != signature(new_entry) {
        let discriminator_value = discriminator(old_entry)
        diagnostics.push(
          Diagnostic::new(
            AbiSignatureCollision,
            abi_section_location(section),
            "\{noun} \{discriminator_value} is used by \"\{signature(old_entry)}\" in the old ABI and \"\{signature(new_entry)}\" in the new ABI",
          ).with_values(
            old_value=signature(old_entry),
            new_value=signature(new_entry),
          ),
        )
      }
    }
  }
}

///|
/// The word used for a callable entry in messages.
fn entry_noun(kind : AbiEntryKind) -> String {
  match kind {
    Function => "function"
    Fallback => "fallback"
    Receive => "receive"
  }
}

///|
/// Canonical output type list, which is what a caller decodes.
fn output_types(entry : AbiFunction) -> String {
  let types : Array[String] = entry.outputs.map(fn(param) { param.type_name })
  types.join(",")
}

///|
/// Which parameters of an event are indexed, as one readable value.
fn indexed_flags(entry : AbiEvent) -> String {
  let flags : Array[String] = entry.inputs.map(fn(param) {
    if param.indexed {
      "indexed"
    } else {
      "not indexed"
    }
  })
  flags.join(", ")
}
