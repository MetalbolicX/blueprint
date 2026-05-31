// ProbeState_test — ProbeState testing

open TestHelpers

suite("ProbeState", () => {
  test("state transitions", () => {
    // Initial state is false
    assert_false(ProbeState.isReady())
    
    ProbeState.setReady()
    assert_true(ProbeState.isReady())
    
    // Setting ready multiple times
    ProbeState.setReady()
    assert_true(ProbeState.isReady())

    // Clean up global state for other tests
    ProbeState.reset()
  })
})
