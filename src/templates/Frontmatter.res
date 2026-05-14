// Parse YAML frontmatter from .ejs.t template files
// Format:
// ---
// to: path/{{ .Name }}.go
// inject: true
// ---
// body content here

open Template

type parseError = {
  message: string,
  line: option<int>,
}

let frontmatterRegex: Js.Re.t = %re("/^---\\n([\\s\\S]*?)\\n---\\n/")

let directiveRegex: Js.Re.t = %re("/^(\\w+):\\s*(.*)$/")

let parseDirective: string => option<directive> = line => {
  let regexMatch = Js.String.match directiveRegex, line
  switch regexMatch {
  | Some(matches) if Js.Array.length(matches) >= 3 => {
    let key = matches[1]
    let value = matches[2]
    switch key {
    | "to" => Some(To(value))
    | "inject" => Some(Inject(value))
    | "after" => Some(After(value))
    | "before" => Some(Before(value))
    | "prepend" if value == "" || value == "true" => Some(Prepend)
    | "append" if value == "" || value == "true" => Some(Append)
    | "force" if value == "" || value == "true" => Some(Force)
    | "sh" => Some(Sh(value))
    | _ => None  // unknown directive, skip for forward compat
    }
  }
  | _ => None
  }
}

type parsedFrontmatter = {
  directives: array<directive>,
  body: string,
}

let parse: string => result<parsedFrontmatter, string> = content => {
  let matchResult = Js.String.match(frontmatterRegex, content)
  switch matchResult {
  | Some(matches) if Js.Array.length(matches) >= 2 => {
    let frontmatterStr = matches[1]
    let body = Js.String.replace(frontmatterRegex, "", content)

    // Parse each line of frontmatter as a directive
    let lines = frontmatterStr->Js.String.split("\n")->Js.Array.filter(l => l != "")
    let directives = lines->Js.Array.map(parseDirective)->Js.Array.filterMap(x => x)

    Ok({ directives: directives, body: body })
  }
  | _ => Error("Missing or invalid frontmatter delimiter")
  }
}