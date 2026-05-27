/**
 * PathSecurity — path traversal protection
 * Provides utilities for validating paths are within allowed directory trees
 */

/**
 * Checks if a path is within a root directory tree.
 * Uses Path.resolve to normalize both paths, then symlink resolution via fs.realpath,
 * then verifies the resolved path starts with root + path separator.
 *
 * @param path - The path to check (can be relative or absolute)
 * @param root - The root directory that path must be within
 * @param pathAdapter - Path operations
 * @param fs - File system operations (for realpath symlink resolution)
 * @returns promise<true> if path is inside root tree, false otherwise
 */
let isWithinTree: (string, string, Ports.path, Ports.fileSystem) => promise<bool>