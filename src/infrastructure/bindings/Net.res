/**
 * Net — typed binding for node:net.
 * Lives in its own file (not Net = {...} inside NodeJs.res) so ReScript's
 * tree-shaker keeps the module even when no other compiled caller exists in
 * the same incremental pass — this avoids the "unused module" cascade that
 * would otherwise prune `isIP` away while SsrfGuard is breaking.
 */

@module("node:net")
external isIP: string => int = "isIP"
