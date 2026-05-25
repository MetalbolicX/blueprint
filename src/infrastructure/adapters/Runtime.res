let isDeno: unit => bool = %raw(`
  function() {
    return typeof Deno !== "undefined";
  }
`)
