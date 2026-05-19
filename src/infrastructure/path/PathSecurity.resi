/**
 * PathSecurity — path traversal protection
 * Provides utilities for validating paths are within allowed directory trees
 */

/**
 * Checks if a path is within a root directory tree.
 * Uses Path.resolve to normalize both paths, then verifies
 * the resolved path starts with root + path separator.
 *
 * @param path - The path to check (can be relative or absolute)
 * @param root - The root directory that path must be within
 * @returns true if path is inside root tree, false otherwise
 */
let isWithinTree: (string, string) => bool