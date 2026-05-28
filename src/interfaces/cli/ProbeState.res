let ready = ref(false)

let setReady = () => {
  ready := true
}

let isReady = () => ready.contents
