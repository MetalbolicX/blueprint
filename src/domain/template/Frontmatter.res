// Parse YAML frontmatter from .ejs.t template files
// Format:
// ---
// to: path/{{ .Name }}.go
// inject: true
// ---
// body content here

open Template

@@warning("-34")
type parseError = {
  message: string,
  line?: int,
}

// URL type for scheme validation
type jsUrl

@new
external makeUrl: string => jsUrl = "URL"

@get
external urlProtocol: jsUrl => string = "protocol"

// Path absolute check (uses node:path directly to avoid infrastructure module prefix)
@module("node:path")
external pathIsAbsolute: string => bool = "isAbsolute"

let frontmatterRegex: RegExp.t = /^---\r?\n([\s\S]*?)\r?\n---\r?\n/

let directiveRegex: RegExp.t = /^(\w+):\s*(.*)$/

// Reject paths that are absolute or contain parent-segment escapes
let rejectUnsafePath: string => result<string, string> = value => {
  if pathIsAbsolute(value) {
    Error("Absolute paths are not allowed: " ++ value)
  } else {
    // Check for ".." segment (parent directory escape) in both / and \ separators
    let segments = Js.String.split("/", value)
    let hasParentSegment = segments->Belt.Array.some(s => s == "..")
    if hasParentSegment {
      Error("Paths with '..' segment are not allowed: " ++ value)
    } else {
      // Also check backslash separator
      let backslashSegments = Js.String.split("\\", value)
      let hasParentSegmentBackslash = backslashSegments->Belt.Array.some(s => s == "..")
      if hasParentSegmentBackslash {
        Error("Paths with '..' segment are not allowed: " ++ value)
      } else {
        Ok(value)
      }
    }
  }
}

// Require http or https URL scheme
let requireHttpUrl: string => result<string, string> = value => {
  try {
    let url = makeUrl(value)
    let proto = urlProtocol(url)
    if proto == "http:" || proto == "https:" {
      Ok(value)
    } else {
      Error("Only http/https URLs are allowed, got: " ++ proto)
    }
  } catch {
  | _ => Error("Invalid URL: " ++ value)
  }
}

// Helper to check directive type
let checkDirective: (string, string) => result<directive, string> = (key, value) => {
  if key == "to" {
    switch rejectUnsafePath(value) {
    | Ok(path) => Ok(To(path))
    | Error(msg) => Error(msg)
    }
  } else if key == "from" {
    switch rejectUnsafePath(value) {
    | Ok(path) => Ok(From(path))
    | Error(msg) => Error(msg)
    }
  } else if key == "inject" {
    Ok(Inject(value))
  } else if key == "after" {
    Ok(After(value))
  } else if key == "before" {
    Ok(Before(value))
  } else if key == "at_line" {
    switch Int.fromString(value) {
    | Some(n) => Ok(AtLine(n))
    | None => Error("Invalid at_line directive: " ++ value)
    }
  } else if key == "skip_if" {
    Ok(SkipIf(value))
  } else if key == "prepend" && (value == "" || value == "true") {
    Ok(Prepend)
  } else if key == "append" && (value == "" || value == "true") {
    Ok(Append)
  } else if key == "eof_last" && (value == "" || value == "true") {
    Ok(EofLast)
  } else if key == "force" && (value == "" || value == "true") {
    Ok(Force)
  } else if key == "unless_exists" && (value == "" || value == "true") {
    Ok(UnlessExists)
  } else if key == "tool" {
    Ok(Tool(value))
  } else if key == "fetch" {
    switch requireHttpUrl(value) {
    | Ok(url) => Ok(Fetch(url))
    | Error(msg) => Error(msg)
    }
  } else if key == "script" {
    Ok(Script(value))
  } else if key == "sh" {
    Error("Unsupported directive: sh")
  } else {
    Error("Unknown directive: " ++ key)
  }
}

// Parse directive - convert Js.String.t to string explicitly
let parseDirective: string => result<directive, string> = line => {
  let matches = Js.String.match_(directiveRegex, line)
  switch matches {
  | None => Error("Invalid directive syntax: " ++ line)
  | Some(arr) =>
    if Array.length(arr) < 3 {
      Error("Invalid directive syntax: " ++ line)
    } else {
      let keyOpt = arr[1]
      let valueOpt = arr[2]
      // Convert option<Js.String.t> to option<string> using Obj.magic
      let keyStr: option<string> = Obj.magic(keyOpt)
      let valueStr: option<string> = Obj.magic(valueOpt)
      switch (keyStr, valueStr) {
      | (Some(k), Some(v)) => checkDirective(k, v)
      | _ => Error("Invalid directive syntax: " ++ line)
      }
    }
  }
}

type parsedFrontmatter = {
  directives: array<directive>,
  body: string,
}

let parse: string => result<parsedFrontmatter, string> = content => {
  let matches = Js.String.match_(frontmatterRegex, content)
  switch matches {
  | None => Error("Missing or invalid frontmatter delimiter")
  | Some(arr) =>
    if Array.length(arr) < 2 {
      Error("Missing or invalid frontmatter delimiter")
    } else {
      let fsOpt = arr[1]
      let fsStr: option<string> = Obj.magic(fsOpt)
      switch fsStr {
      | Some(fs) => {
          let body = Js.String.replaceByRe(frontmatterRegex, "", content)
          let lines = Js.String.split("\n", fs)->Array.filter(l => l !== "")
          switch lines->Array.reduce(Ok([]), (acc, line) => {
            switch acc {
            | Error(e) => Error(e)
            | Ok(directives) =>
              switch parseDirective(line) {
              | Ok(directive) => Ok(directives->Array.concat([directive]))
              | Error(e) => Error(e)
              }
            }
          }) {
          | Ok(directives) => Ok({directives, body})
          | Error(e) => Error(e)
          }
        }
      | None => Error("Missing frontmatter content")
      }
    }
  }
}
