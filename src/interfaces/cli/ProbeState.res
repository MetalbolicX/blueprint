let ready = ref(false)

let reset = () => {
  ready := false
}

let setReady = () => {
  ready := true
}

let isReady = () => ready.contents
