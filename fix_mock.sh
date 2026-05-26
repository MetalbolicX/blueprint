sed -i 's/globalThis.Deno = {/globalThis.Deno = {\n        env: { toObject: () => process.env },/g' test/Hooks_test.res
