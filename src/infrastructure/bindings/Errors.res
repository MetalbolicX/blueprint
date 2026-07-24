// Error message extraction helper
// Promise.catch handlers receive `exn` (not JsExn.t);
// Obj.magic bridges into JsExn.t for message extraction.
let extractErrorMessage = (e: exn): string => {
  switch JsExn.message(e->Obj.magic) {
  | Some(m) => m
  | None => "Unknown error"
  }
}
