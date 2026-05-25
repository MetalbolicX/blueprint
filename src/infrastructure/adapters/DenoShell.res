open Ports

let execShellCommandRaw: (string, option<string>) => promise<result<string, string>> = %raw(`
  async (command, cwdOpt) => {
    try {
      let cwd = cwdOpt !== undefined && cwdOpt !== null ? cwdOpt : undefined;
      const cmd = new Deno.Command("sh", {
        args: ["-c", command],
        cwd: cwd,
        stdout: "piped",
        stderr: "piped"
      });
      const output = await cmd.output();
      const decoder = new TextDecoder();
      const stdout = decoder.decode(output.stdout);
      const stderr = decoder.decode(output.stderr);
      
      if (output.code === 0) {
        return { TAG: "Ok", _0: stdout };
      } else {
        return { TAG: "Error", _0: stderr || stdout || ("Command failed with code " + output.code) };
      }
    } catch (e) {
      return { TAG: "Error", _0: e.message || String(e) };
    }
  }
`)

let execAsyncRaw: (string, option<shellOptions>) => promise<execResult> = %raw(`
  async (cmdString, optionsOpt) => {
    try {
      const options = optionsOpt !== undefined && optionsOpt !== null ? optionsOpt : {};
      const cwd = options.cwd !== undefined ? options.cwd : undefined;
      const env = options.env !== undefined ? options.env : undefined;
      
      let executable = "sh";
      let args = ["-c", cmdString];
      
      const cmd = new Deno.Command(executable, {
        args: args,
        cwd: cwd,
        env: env,
        stdout: "piped",
        stderr: "piped"
      });
      const output = await cmd.output();
      const decoder = new TextDecoder();
      
      return {
        stdout: decoder.decode(output.stdout),
        stderr: decoder.decode(output.stderr),
        status: output.code,
        signalCode: output.signal,
        killed: false
      };
    } catch (e) {
      return {
        stdout: "",
        stderr: e.message || String(e),
        status: 1,
        signalCode: undefined,
        killed: false
      };
    }
  }
`)

let execFileAsyncRaw: (string, option<array<string>>, option<shellOptions>) => promise<execResult> = %raw(`
  async (executable, argsOpt, optionsOpt) => {
    try {
      const args = argsOpt !== undefined && argsOpt !== null ? argsOpt : [];
      const options = optionsOpt !== undefined && optionsOpt !== null ? optionsOpt : {};
      const cwd = options.cwd !== undefined ? options.cwd : undefined;
      const env = options.env !== undefined ? options.env : undefined;
      
      const cmd = new Deno.Command(executable, {
        args: args,
        cwd: cwd,
        env: env,
        stdout: "piped",
        stderr: "piped"
      });
      const output = await cmd.output();
      const decoder = new TextDecoder();
      
      return {
        stdout: decoder.decode(output.stdout),
        stderr: decoder.decode(output.stderr),
        status: output.code,
        signalCode: output.signal,
        killed: false
      };
    } catch (e) {
      return {
        stdout: "",
        stderr: e.message || String(e),
        status: 1,
        signalCode: undefined,
        killed: false
      };
    }
  }
`)

let make: unit => shell = () => {
  {
    execShellCommand: (~command, ~cwd=?) => execShellCommandRaw(command, cwd),
    execAsync: (cmd, ~options=?) => execAsyncRaw(cmd, options),
    execFileAsync: (cmd, ~args=?, ~options=?) => execFileAsyncRaw(cmd, args, options),
  }
}
