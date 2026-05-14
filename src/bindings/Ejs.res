type options = {
  delimiter: option<string>,
  escape: option<string => string>,
}

@module("ejs")
external render: (string, dict<string>, ~options: options=?) => string = "render"

@module("ejs")
external renderFile: (string, dict<string>, ~options: options=?) => promise<string> = "renderFile"
