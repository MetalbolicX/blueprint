type options = {
  delimiter?: string,
  escape?: string => string,
}

let render: (string, dict<string>, ~options: options=?) => string
let renderFile: (string, dict<string>, ~options: options=?) => promise<string>
