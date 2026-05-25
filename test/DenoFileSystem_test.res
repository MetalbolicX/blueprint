open TestHelpers

suite("DenoFileSystem adapter", () => {
  testAsync("reads file via Deno.readTextFile", resolve => {
    let _ = (async () => {
      // Setup Deno mock
      let _ = %raw(`
        globalThis.Deno = {
          readTextFile: async (path) => path === "/test.txt" ? "mock data" : "wrong"
        }
      `)
      let fs = DenoFileSystem.make()
      let data = await fs.readFile("/test.txt")
      
      assert_eq(data, "mock data")
      resolve()
    })()
  })
})
