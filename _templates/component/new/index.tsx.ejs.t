---
to: <%= path %>/<%= name %>.tsx
---
import React from 'react'

interface <%= name %>Props {
  children?: React.ReactNode
}

export const <%= name %>: React.FC<<%= name %>Props> = ({ children }) => {
  return <div className="<%= h.kebabCase(name) %>"><%= children %></div>
}