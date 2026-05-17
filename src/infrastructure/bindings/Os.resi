type cpusTimes = {user: int, nice: int, sys: int, idle: int, irq: int}

type cpusInfo = {
  model: string,
  speed: int,
  times: cpusTimes,
}

type networkInterfaceInfo = {
  address: string,
  family: string,
  netmask: string,
  mac: string,
  internal: bool,
}

type userInfoOptions = {encoding: string}

type userInfoResult = {
  username: string,
  uid: int,
  gid: int,
  shell: string,
  homedir: string,
}

let tmpdir: unit => string
let homedir: unit => string
let hostname: unit => string
let platform: unit => string
let arch: unit => string
let cpus: unit => array<cpusInfo>
let totalmem: unit => int
let freemem: unit => int
let loadavg: unit => array<float>
let uptime: unit => int
let networkInterfaces: unit => dict<array<networkInterfaceInfo>>
let userInfo: (~options: userInfoOptions=?) => userInfoResult

let makeStagingDir: unit => string
