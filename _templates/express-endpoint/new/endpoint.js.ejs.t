---
to: routes/<%= h.kebabCase(name) %>.js
---
const express = require('express')
const router = express.Router()

// GET /<%= h.kebabCase(name) %>
router.get('/', (req, res) => {
  res.status(200).json({
    message: '<%= name %> resource',
    items: [],
  })
})

// GET /<%= h.kebabCase(name) %>/:id
router.get('/:id', (req, res) => {
  const { id } = req.params
  res.status(200).json({
    message: '<%= name %> resource',
    id,
  })
})

// POST /<%= h.kebabCase(name) %>
router.post('/', (req, res) => {
  const { body } = req
  const data = body || {}
  res.status(201).json({
    message: '<%= name %> created',
    data,
  })
})

// PUT /<%= h.kebabCase(name) %>/:id
router.put('/:id', (req, res) => {
  const { id } = req.params
  const { body } = req
  const data = body || {}
  res.status(200).json({
    message: '<%= name %> updated',
    id,
    data,
  })
})

// DELETE /<%= h.kebabCase(name) %>/:id
router.delete('/:id', (req, res) => {
  const { id } = req.params
  res.status(200).json({
    message: '<%= name %> deleted',
    id,
  })
})

module.exports = router
