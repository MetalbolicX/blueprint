let suite = (_name, fn) => fn()

let test = Test.test
let testAsync = Test.testAsync
let assertion = Test.assertion

let assert_eq = (a, b) =>
  assertion(~operator="==", (a, b) => a == b, a, b)

let assert_true = a =>
  assertion(~operator="==", (a, b) => a == b, a, true)

let assert_false = a =>
  assertion(~operator="==", (a, b) => a == b, a, false)
