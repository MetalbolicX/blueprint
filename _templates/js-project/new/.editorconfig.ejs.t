---
to: .editorconfig
sh: curl -sL "https://www.toptal.com/developers/gitignore/api/node" -o .gitignore && npm install
---
# Editor configuration, see https://editorconfig.org
root = true

[*]
charset = utf-8
indent_style = space
indent_size = 2
insert_final_newline = true
trim_trailing_whitespace = true

[*.js]
quote_type = double

[*.md]
max_line_length = off
trim_trailing_whitespace = false