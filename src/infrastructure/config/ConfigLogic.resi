// ConfigLogic.resi
open ConfigTypes

let mergeConfig: (~global: globalConfig, ~project: option<config>) => mergedConfig
let validateMergedConfig: mergedConfig => result<unit, string>
