@module("node:os")
external tmpdir: unit => string = "tmpdir"

@module("node:os")
external homedir: unit => string = "homedir"

@module("node:os")
external hostname: unit => string = "hostname"

@module("node:os")
external platform: unit => string = "platform"

@module("node:os")
external arch: unit => string = "arch"

@module("node:os")
external cpus: unit => array<{
  model: string,
  speed: int,
  times: {user: int, nice: int, sys: int, idle: int, irq: int},
}> = "cpus"

@module("node:os")
external totalmem: unit => int = "totalmem"

@module("node:os")
external freemem: unit => int = "freemem"

@module("node:os")
external loadavg: unit => array<float> = "loadavg"

@module("node:os")
external uptime: unit => int = "uptime"

type eol = {LF: string, CRLF: string}

@module("node:os")
external eol: eol = "EOL"

@module("node:os")
external networkInterfaces: unit => Js.Dict.t<array<{address: string, family: string, netmask: string, mac: string, internal: bool}>> = "networkInterfaces"

@module("node:os")
external userInfo: (~options: {encoding: string}=?) => {username: string, uid: int, gid: int, shell: string, homedir: string} = "userInfo"

let makeStagingDir: unit => string = () => {
  let randomPart = Js.Math.random() -> Js.Float.toString -> Js.String.substring(~from=2)
  Node.Path.join(Node.Os.tmpdir(), "fluxo-" ++ randomPart)
}