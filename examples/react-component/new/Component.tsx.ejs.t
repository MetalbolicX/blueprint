---
to: <%= path %>/<%= name %>.tsx
---
import React from 'react'

interface <%= name %>Props {
  children?: React.ReactNode
  className?: string
}

export const <%= name %>: React.FC<<%= name %>Props> = ({
  children,
  className = '',
}) => {
  return (
    <div className={`<%= h.kebabCase(name) %> ${className}`}>
      <%= children %>
    </div>
  )
}