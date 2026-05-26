open Ports

let decodeBytes: (array<int>) => string = %raw(`
  function(bytes) {
    return new TextDecoder().decode(new Uint8Array(bytes));
  }
`)

let execShellCommandRaw: (string, option<string>) => promise<result<string, string>> = async (
  command,
  cwdOpt,
) => {
  let cmd = Deno.Command.make(
    "sh",
    {
      args: ["-c", command],
      cwd: ?cwdOpt,
      stdout: "piped",
      stderr: "piped",
    },
  )
  let output = await Deno.Command.output(cmd)
  let stdout = decodeBytes(output.stdout)
  let stderr = decodeBytes(output.stderr)

  if output.code == 0 {
    Ok(stdout)
  } else {
    Error(stderr !== "" ? stderr : stdout !== "" ? stdout : "Command failed with code " ++ Belt.Int.toString(output.code))
  }
}

let execAsyncRaw: (string, option<shellOptions>) => promise<execResult> = async (
  cmdString,
  optionsOpt,
) => {
  let options = optionsOpt->Belt.Option.getWithDefault({})
  let cmd = Deno.Command.make(
    "sh",
    {
      args: ["-c", cmdString],
      cwd: ?options.cwd,
      env: ?options.env,
      stdout: "piped",
      stderr: "piped",
      timeout: ?options.timeout,
    },
  )
  let output = await Deno.Command.output(cmd)
  {
    stdout: decodeBytes(output.stdout),
    stderr: decodeBytes(output.stderr),
    status: Some(output.code),
    signalCode: Nullable.toOption(output.signal),
    killed: output.signal !== null,
  }
}

let execFileAsyncRaw: (
  string,
  option<array<string>>,
  option<shellOptions>,
) => promise<execResult> = async (executable, argsOpt, optionsOpt) => {
  let args = argsOpt->Belt.Option.getWithDefault([])
  let options = optionsOpt->Belt.Option.getWithDefault({})
  let cmd = Deno.Command.make(
    executable,
    {
      args: args,
      cwd: ?options.cwd,
      env: ?options.env,
      stdout: "piped",
      stderr: "piped",
      timeout: ?options.timeout,
    },
  )
  let output = await Deno.Command.output(cmd)
  {
    stdout: decodeBytes(output.stdout),
    stderr: decodeBytes(output.stderr),
    status: Some(output.code),
    signalCode: Nullable.toOption(output.signal),
    killed: output.signal !== null,
  }
}

let make: unit => shell = () => {
  {
    execShellCommand: (~command, ~cwd=?) => execShellCommandRaw(command, cwd),
    execAsync: (cmd, ~options=?) => execAsyncRaw(cmd, options),
    execFileAsync: (cmd, ~args=?, ~options=?) => execFileAsyncRaw(cmd, args, options),
  }
}
