// Case conversion helpers available in EJS templates as h.*
// Mirrors Go version's funcmaps from internal/templates/funcmaps.go

let capitalize: string => string = s => {
  let len = Js.String.length(s)
  if len == 0 {
    s
  } else {
    let first = Js.String.charAt(0, s)->Js.String.toUpperCase
    let rest = Js.String.sliceToEnd(s, ~from=1)
    first ++ rest
  }
}

let uncapitalize: string => string = s => {
  let len = Js.String.length(s)
  if len == 0 {
    s
  } else {
    let first = Js.String.charAt(0, s)->Js.String.toLowerCase
    let rest = Js.String.sliceToEnd(s, ~from=1)
    first ++ rest
  }
}

// Split on underscore, dash, and camelCase boundaries
let splitIntoWords: string => array<string> = s => {
  // First replace dashes and underscores with spaces
  let withSpaces = s->Js.String.replaceByRe(%re("/-/"), " ")->Js.String.replaceByRe(%re("/_/"), " ")
  // Split camelCase: aB -> a B, ABC -> A B C
  let splitCamel = withSpaces->Js.String.replaceByRe(%re("/([a-z])([A-Z])/g"), "$1 $2")
  // Handle consecutive uppercase before lowercase: ABc -> A B c
  let splitCaps = splitCamel->Js.String.replaceByRe(%re("/([A-Z]+)([A-Z][a-z])/g"), "$1 $2")
  splitCaps->Js.String.split(" ")->Js.Array.filter(s => s != "")
}

let pascalCase: string => string = s => {
  s->splitIntoWords->Js.Array.map(capitalize)->Js.Array.join("")
}

let camelCase: string => string = s => {
  let words = s->splitIntoWords
  if Js.Array.length(words) == 0 {
    s
  } else {
    let first = words[0]->Option.getExn->uncapitalize
    let rest = Js.Array.sliceFrom(words, 1)->Js.Array.map(capitalize)->Js.Array.join("")
    first ++ rest
  }
}

let kebabCase: string => string = s => {
  s->splitIntoWords->Js.Array.map(Js.String.toLowerCase)->Js.Array.join("-")
}

let snakeCase: string => string = s => {
  s->splitIntoWords->Js.Array.map(Js.String.toLowerCase)->Js.Array.join("_")
}

let upper: string => string = Js.String.toUpperCase
let lower: string => string = Js.String.toLowerCase
let trim: string => string = Js.String.trim
let title: string => string = s => {
  s->Js.String.split(" ")->Js.Array.map(s => s->capitalize->Js.String.toLowerCase)->Js.Array.join(" ")
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
    pascalCase: pascalCase,
    camelCase: camelCase,
    kebabCase: kebabCase,
    snakeCase: snakeCase,
    upper: upper,
    lower: lower,
    trim: trim,
    title: title,
    capitalize: capitalize,
    uncapitalize: uncapitalize,
  }
}