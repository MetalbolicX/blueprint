/**
 * Asserts that a text value matches an expected string.
 * @param {string} expected - The expected string value
 * @param {string} actual - The actual string value to test
 * @param {string=} message - Optional custom message to display on assertion failure
 * @returns {unit}
 */
let isTextEqualTo: (string, string, ~message: string=?) => unit

/**
 * Asserts that an integer value matches an expected integer.
 * @param {int} expected - The expected integer value
 * @param {int} actual - The actual integer value to test
 * @param {string=} message - Optional custom message to display on assertion failure
 * @returns {unit}
 */
let isIntEqualTo: (int, int, ~message: string=?) => unit

/**
 * Explicitly marks a test as passed with a custom message.
 * @param {string} message - Success message to display
 * @returns {unit}
 */
let passWith: string => unit

/**
 * Explicitly fails a test with a custom message.
 * @param {string} message - Failure message to display
 * @returns {unit}
 * @throws Will throw an exception to fail the current test
 */
let failWith: string => unit
