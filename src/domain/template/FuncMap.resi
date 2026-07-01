let capitalize: string => string
let uncapitalize: string => string
let pascalCase: string => string
let camelCase: string => string
let kebabCase: string => string
let snakeCase: string => string
let upper: string => string
let lower: string => string
let trim: string => string
let title: string => string

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

let makeHelpers: unit => helpers

let makeHelpersDict: unit => dict<string => string>
