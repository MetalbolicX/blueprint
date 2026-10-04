// Error message extraction helper
// catch handlers receive JsExn-wrapped exceptions; unwrap before reading message.
let extractErrorMessage = (e: exn, ~fallback="Unknown error"): string => {
  switch e {
  | JsExn(obj) =>
    switch JsExn.message(obj) {
    | Some(m) => m
    | None => fallback
    }
  | _ => fallback
  }
}

// Keep Node error-code extraction alongside message unwrapping so callers do not
// need to inspect JsExn objects directly.
let extractErrorCode = (e: exn): option<string> => {
  switch e {
  | JsExn(obj) => Obj.magic(obj)["code"]
  | _ => None
  }
}
