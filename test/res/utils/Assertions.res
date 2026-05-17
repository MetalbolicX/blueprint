open Test

/**
 * Asserts that a text value matches an expected string.
 * @param {string} originalText - The expected string value
 * @param {string} textToCompare - The actual string value to test
 * @param {string=} message - Optional custom message to display on assertion failure
 * @returns {unit}
 */
let isTextEqualTo: (string, string, ~message: string=?) => unit = (
  originalText,
  textToCompare,
  ~message as msg="",
) =>
  assertion(
    (originalText, textToCompare) => originalText->String.equal(textToCompare),
    originalText,
    textToCompare,
    ~operator="String equals to",
    ~message=msg,
  )

/**
 * Asserts that a boolean value is true.
 * @param {bool} a - The boolean value to test
 * @param {string=} message - Optional custom message to display on assertion failure
 * @returns {unit}
 */
let isTruthy: (bool, ~message: string=?) => unit = (a, ~message as msg="") =>
  assertion((a, b) => a == b, a, true, ~operator="Equals to true", ~message=msg)

/**
 * Asserts that an integer value matches an expected integer.
 * @param {int} a - The expected integer value
 * @param {int} b - The actual integer value to test
 * @param {string=} message - Optional custom message to display on assertion failure
 * @returns {unit}
 */
let isIntEqualTo: (int, int, ~message: string=?) => unit = (a, b, ~message as msg="") =>
  assertion((a, b) => a == b, a, b, ~operator="Integer equals to", ~message=msg)

/**
 * Explicitly marks a test as passed with a custom message.
 * @param {string} message - Success message to display
 * @returns {unit}
 */
let passWith: string => unit = message => isTruthy(true, ~message)

/**
 * Explicitly fails a test with a custom message.
 * @param {string} message - Failure message to display
 * @returns {unit}
 * @throws Will throw an exception to fail the current test
 */
let failWith: string => unit = message => isTruthy(false, ~message)
