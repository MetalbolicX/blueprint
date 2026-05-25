/**
 * Deno path adapter implementing Ports.path.
 * Deno provides excellent node:path compatibility, which we utilize here.
 */

@module("node:path") external join: (string, string) => string = "join"
@module("node:path") external resolve: (string, string) => string = "resolve"
@module("node:path") external dirname: string => string = "dirname"
@module("node:path") external isAbsolute: string => bool = "isAbsolute"
@module("node:path") external basename: (string, ~ext: string=?) => string = "basename"

let make: unit => Ports.path = () => {
  join: join,
  resolve: resolve,
  dirname: dirname,
  isAbsolute: isAbsolute,
  basename: (path, ~ext=?) => basename(path, ~ext=?ext),
}
