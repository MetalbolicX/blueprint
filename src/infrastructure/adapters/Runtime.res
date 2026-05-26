let isDeno: unit => bool = %raw("() => typeof Deno !== 'undefined'")
