const express = require('express')
const router = express.Router()

// GET /user
router.get('/', (req, res) => {
  res.status(200).json({
    message: 'User resource',
    items: [],
  })
})

// GET /user/:id
router.get('/:id', (req, res) => {
  const { id } = req.params
  res.status(200).json({
    message: 'User resource',
    id,
  })
})

// POST /user
router.post('/', (req, res) => {
  const { body } = req
  const data = body || {}
  res.status(201).json({
    message: 'User created',
    data,
  })
})

// PUT /user/:id
router.put('/:id', (req, res) => {
  const { id } = req.params
  const { body } = req
  const data = body || {}
  res.status(200).json({
    message: 'User updated',
    id,
    data,
  })
})

// DELETE /user/:id
router.delete('/:id', (req, res) => {
  const { id } = req.params
  res.status(200).json({
    message: 'User deleted',
    id,
  })
})

module.exports = router
