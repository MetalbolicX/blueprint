---
to: src/{{ .name }}_test.go
---
package main

import "testing"

func Test{{ pascalCase .name }}(t *testing.T) {
    t.Log("Testing {{ .name }}")
}