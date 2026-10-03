open Ports

let make: unit => fetcher = () => {
  fetch: url => Fetcher.fetch(url),
  clearCache: () => Fetcher.clearCache(),
}
