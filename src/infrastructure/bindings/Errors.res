// Error message extraction helper
// catch handlers receive JsExn-wrapped exceptions; unwrap before reading message.
let extractErrorMessage = (e: exn): string => {
  switch e {
  | JsExn(obj) =>
    switch JsExn.message(obj) {
    | Some(m) => m
    | None => "Unknown error"
    }
  | _ => "Unknown error"
  }
}
