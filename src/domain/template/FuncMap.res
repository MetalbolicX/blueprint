// Case conversion helpers available in EJS templates as h.*
// Mirrors Go version's funcmaps from internal/templates/funcmaps.go

let capitalize: string => string = s => {
  let len = String.length(s)
  if len == 0 {
    s
  } else {
    let first = String.getUnsafe(s, 0)->String.toUpperCase
    let rest = String.slice(s, ~start=1)
    first ++ rest
  }
}

let uncapitalize: string => string = s => {
  let len = String.length(s)
  if len == 0 {
    s
  } else {
    let first = String.getUnsafe(s, 0)->String.toLowerCase
    let rest = String.slice(s, ~start=1)
    first ++ rest
  }
}

// Split on underscore, dash, and camelCase boundaries
let splitIntoWords: string => array<string> = s => {
  // First replace dashes and underscores with spaces
  let withDashes = Js.String.replaceByRe(/-/, " ", s)
  let withSpaces = Js.String.replaceByRe(/_/, " ", withDashes)
  // Split camelCase: aB -> a B, ABC -> A B C
  let splitCamel = Js.String.replaceByRe(/([a-z])([A-Z])/g, "$1 $2", withSpaces)
  // Handle consecutive uppercase before lowercase: ABc -> A B c
  let splitCaps = Js.String.replaceByRe(/([A-Z]+)([A-Z][a-z])/g, "$1 $2", splitCamel)
  Js.String.split(" ", splitCaps)->Array.filter(word => word !== "")
}

let pascalCase: string => string = s => {
  s->splitIntoWords->Array.map(capitalize)->Array.join("")
}

let camelCase: string => string = s => {
  let words = s->splitIntoWords
  if Array.length(words) == 0 {
    s
  } else {
    let first = words[0]->Option.getOrThrow->uncapitalize
    let rest = Array.slice(words, ~start=1)->Array.map(capitalize)->Array.join("")
    first ++ rest
  }
}

let kebabCase: string => string = s => {
  s->splitIntoWords->Array.map(String.toLowerCase)->Array.join("-")
}

let snakeCase: string => string = s => {
  s->splitIntoWords->Array.map(String.toLowerCase)->Array.join("_")
}

let upper: string => string = String.toUpperCase
let lower: string => string = String.toLowerCase
let trim: string => string = String.trim
let title: string => string = s => {
  Js.String.split(" ", s)->Array.map(s => s->capitalize->String.toLowerCase)->Array.join(" ")
}

// Export helpers object for EJS
type helpers = {
  pascalCase: string => string,
  camelCase: string => string,
  kebabCase: string => string,
  snakeCase: string => string,
  upper: string => string,
  lower: string => string,
  trim: string => string,
  title: string => string,
  capitalize: string => string,
  uncapitalize: string => string,
}

let makeHelpers: unit => helpers = () => {
  {
    pascalCase,
    camelCase,
    kebabCase,
    snakeCase,
    upper,
    lower,
    trim,
    title,
    capitalize,
    uncapitalize,
  }
}
