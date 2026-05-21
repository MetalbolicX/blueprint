// ShellConfig_test — new shell configuration parsing tests

open TestHelpers

suite("ShellConfig", () => {
  test("parseShellConfig: shell.enabled: false is parsed correctly", () => {
    let yaml = "
shell:
  enabled: false
"
    let parsed = Config.parse(yaml)
    switch parsed {
    | Ok(cfg) => {
        switch cfg.shell {
        | Some(shell) => assert_eq(shell.enabled, false)
        | None => assert_false(true)
        }
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parseShellConfig: shell.enabled: true is parsed correctly", () => {
    let yaml = "
shell:
  enabled: true
"
    let parsed = Config.parse(yaml)
    switch parsed {
    | Ok(cfg) => {
        switch cfg.shell {
        | Some(shell) => assert_eq(shell.enabled, true)
        | None => assert_false(true)
        }
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parseShellConfig: shell.tools[].name is parsed correctly", () => {
    let yaml = "
shell:
  enabled: true
  tools:
    - name: format
      command: npx prettier --write .
"
    let parsed = Config.parse(yaml)
    switch parsed {
    | Ok(cfg) => {
        switch cfg.shell {
        | Some(shell) => {
            switch shell.tools {
            | Some(tools) => {
                let formatTool = tools->Array.find(t => t.name == "format")
                switch formatTool {
                | Some(t) => assert_eq(t.name, "format")
                | None => assert_false(true)
                }
              }
            | None => assert_false(true)
            }
          }
        | None => assert_false(true)
        }
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parseShellConfig: shell.tools[].command is parsed correctly", () => {
    let yaml = "
shell:
  enabled: true
  tools:
    - name: format
      command: npx prettier --write .
"
    let parsed = Config.parse(yaml)
    switch parsed {
    | Ok(cfg) => {
        switch cfg.shell {
        | Some(shell) => {
            switch shell.tools {
            | Some(tools) => {
                let formatTool = tools->Array.find(t => t.name == "format")
                switch formatTool {
                | Some(t) => assert_eq(t.command, "npx prettier --write .")
                | None => assert_false(true)
                }
              }
            | None => assert_false(true)
            }
          }
        | None => assert_false(true)
        }
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parseShellConfig: shell.tools[].args is optional and parsed correctly", () => {
    let yaml = "
shell:
  enabled: true
  tools:
    - name: build
      command: npm run build
      args:
        - --prod
        - --no-cache
"
    let parsed = Config.parse(yaml)
    switch parsed {
    | Ok(cfg) => {
        switch cfg.shell {
        | Some(shell) => {
            switch shell.tools {
            | Some(tools) => {
                let buildTool = tools->Array.find(t => t.name == "build")
                switch buildTool {
                | Some(t) => {
                    switch t.args {
                    | Some(args) => {
                        assert_eq(Array.length(args), 2)
                        switch args[0] {
                        | Some(first) => assert_eq(first, "--prod")
                        | None => assert_false(true)
                        }
                        switch args[1] {
                        | Some(second) => assert_eq(second, "--no-cache")
                        | None => assert_false(true)
                        }
                      }
                    | None => assert_false(true)
                    }
                  }
                | None => assert_false(true)
                }
              }
            | None => assert_false(true)
            }
          }
        | None => assert_false(true)
        }
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parseShellConfig: shell.env is parsed correctly", () => {
    let yaml = "
shell:
  enabled: true
  env:
    MY_VAR: custom-value
    ANOTHER_VAR: another-value
"
    let parsed = Config.parse(yaml)
    switch parsed {
    | Ok(cfg) => {
        switch cfg.shell {
        | Some(shell) => {
            switch shell.env {
            | Some(env) => assert_true(Dict.size(env.vars) > 0)
            | None => assert_false(true)
            }
          }
        | None => assert_false(true)
        }
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parseShellConfig: hooks.command is parsed as hookCommand", () => {
    let yaml = "
hooks:
  pre_generate:
    command: ./scripts/pre-generate.sh
"
    let parsed = Config.parse(yaml)
    switch parsed {
    | Ok(cfg) => {
        switch cfg.hooks {
        | Some(hooks) => {
            switch hooks.preGenerate {
            | Some(cmd) => assert_eq(cmd.command, "./scripts/pre-generate.sh")
            | None => assert_false(true)
            }
          }
        | None => assert_false(true)
        }
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parseShellConfig: hooks.args is optional and parsed correctly", () => {
    let yaml = "
hooks:
  post_generate:
    command: npx prettier
    args:
      - --write
      - .
"
    let parsed = Config.parse(yaml)
    switch parsed {
    | Ok(cfg) => {
        switch cfg.hooks {
        | Some(hooks) => {
            switch hooks.postGenerate {
            | Some(cmd) => {
                switch cmd.args {
                | Some(args) => assert_eq(Array.length(args), 2)
                | None => assert_false(true)
                }
              }
            | None => assert_false(true)
            }
          }
        | None => assert_false(true)
        }
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parseShellConfig: multiple tools are parsed", () => {
    let yaml = "
shell:
  enabled: true
  tools:
    - name: lint
      command: npm run lint
    - name: format
      command: npx prettier --write .
    - name: test
      command: pnpm test
      args:
        - --coverage
"
    let parsed = Config.parse(yaml)
    switch parsed {
    | Ok(cfg) => {
        switch cfg.shell {
        | Some(shell) => {
            switch shell.tools {
            | Some(tools) => assert_eq(Array.length(tools), 3)
            | None => assert_false(true)
            }
          }
        | None => assert_false(true)
        }
      }
    | Error(_) => assert_false(true)
    }
  })
})