---
to: <%= path %>/<%= name %>.test.tsx
---
import { describe, it, expect } from 'vitest'
import { render } from '@testing-library/react'
import { <%= name %> } from './<%= name %>'

describe('<%= name %>', () => {
  it('renders children', () => {
    const { getByText } = render(
      <<%= name %>>Hello World</<%= name %>>
    )
    expect(getByText('Hello World')).toBeInTheDocument()
  })

  it('applies custom className', () => {
    const { container } = render(
      <<%= name %> className="custom-class">Content</<%= name %>>
    )
    expect(container.firstChild).toHaveClass('custom-class')
  })
})