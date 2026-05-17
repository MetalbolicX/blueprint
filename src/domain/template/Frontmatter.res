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
  line: option<int>,
}

let frontmatterRegex: RegExp.t = /^---\n([\s\S]*?)\n---\n/

let directiveRegex: RegExp.t = /^(\w+):\s*(.*)$/

// Helper to check directive type
let checkDirective: (string, string) => option<directive> = (key, value) => {
  if key == "to" {
    Some(To(value))
  } else if key == "inject" {
    Some(Inject(value))
  } else if key == "after" {
    Some(After(value))
  } else if key == "before" {
    Some(Before(value))
  } else if key == "prepend" && (value == "" || value == "true") {
    Some(Prepend)
  } else if key == "append" && (value == "" || value == "true") {
    Some(Append)
  } else if key == "force" && (value == "" || value == "true") {
    Some(Force)
  } else if key == "sh" {
    Some(Sh(value))
  } else {
    None
  }
}

// Parse directive - convert Js.String.t to string explicitly
let parseDirective: string => option<directive> = line => {
  let matches = Js.String.match_(directiveRegex, line)
  switch matches {
  | None => None
  | Some(arr) =>
    if Array.length(arr) < 3 {
      None
    } else {
      let keyOpt = arr[1]
      let valueOpt = arr[2]
      // Convert option<Js.String.t> to option<string> using Obj.magic
      let keyStr: option<string> = Obj.magic(keyOpt)
      let valueStr: option<string> = Obj.magic(valueOpt)
      switch (keyStr, valueStr) {
      | (Some(k), Some(v)) => checkDirective(k, v)
      | _ => None
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
          let directives = lines->Array.map(parseDirective)->Array.filterMap(x => x)
          Ok({directives, body})
        }
      | None => Error("Missing frontmatter content")
      }
    }
  }
}
