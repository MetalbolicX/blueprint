type options = {
  delimiter: option<string>,
  escape: option<string => string>,
}

let render: (string, dict<string>, ~options: options=?) => string
let renderFile: (string, dict<string>, ~options: options=?) => promise<string>
