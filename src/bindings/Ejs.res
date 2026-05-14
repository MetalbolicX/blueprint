type options = {
  delimiter: option<string>,
  escape: option<string => string>,
}

@module("ejs")
external render: (string, Js.Dict.t<string>, ~options: options=?) => string = "render"

@module("ejs")
external renderFile: (string, Js.Dict.t<string>, ~options: options=?) => promise<string> = "renderFile"