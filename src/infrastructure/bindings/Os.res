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

type cpusTimes = {user: int, nice: int, sys: int, idle: int, irq: int}
type cpusInfo = {
  model: string,
  speed: int,
  times: cpusTimes,
}

@module("node:os")
external cpus: unit => array<cpusInfo> = "cpus"

@module("node:os")
external totalmem: unit => int = "totalmem"

@module("node:os")
external freemem: unit => int = "freemem"

@module("node:os")
external loadavg: unit => array<float> = "loadavg"

@module("node:os")
external uptime: unit => int = "uptime"

type networkInterfaceInfo = {
  address: string,
  family: string,
  netmask: string,
  mac: string,
  internal: bool,
}

@module("node:os")
external networkInterfaces: unit => dict<array<networkInterfaceInfo>> = "networkInterfaces"

type userInfoOptions = {encoding: string}
type userInfoResult = {username: string, uid: int, gid: int, shell: string, homedir: string}

@module("node:os")
external userInfo: (~options: userInfoOptions=?) => userInfoResult = "userInfo"

let makeStagingDir: unit => string = () => {
  let randomPart = Math.random()->Float.toString->String.slice(~start=2)
  Path.join(tmpdir(), "fluxo-" ++ randomPart)
}
