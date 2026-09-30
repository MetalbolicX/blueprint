open TestHelpers

module Readline = Bindings.NodeJs.Readline

type testStreams = {
  input: Readline.streamReadable,
  output: Readline.streamWritable,
  endInput: unit => unit,
}

let makeStreams: unit => promise<testStreams> = %raw(`
  async function() {
    const {PassThrough} = await import('node:stream');
    const input = new PassThrough();
    const output = new PassThrough();
    return {input, output, endInput: () => input.end()};
  }
`)

suite("NodeJs readline binding", () => {
  testAsync("a pending question rejects when its interface closes", resolve => {
    let _ = (async () => {
      let streams = await makeStreams(())
      let rl = Readline.createInterface(~input=streams.input, ~output=streams.output, ())
      let question = rl.question("Answer: ")
      streams.endInput()
      let rejected = try {
        let _ = await question
        false
      } catch {
      | _ => true
      }
      assert_true(rejected)
      resolve()
    })()
  })
})
