---
to: src/{{ .name }}.go
---
package main

func main() {
    println("Hello, {{ .name }}!")
}