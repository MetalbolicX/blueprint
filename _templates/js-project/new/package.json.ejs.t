---
to: package.json
---
{
  "name": "<%= name %>",
  "version": "0.1.0",
  "description": "<%= description %>",
  "type": "module",
  "author": { "name": "<%= author %>" },
  "repository": {
    "type": "git",
    "url": "https://github.com/<%= githubUsername %>/<%= name %>.git"
  },
  "bugs": {
    "url": "https://github.com/<%= githubUsername %>/<%= name %>/issues"
  },
  "files": ["dist"],
  "license": "<%= license %>",
  <% if (flavor === 'node') { %>
  "engines": { "node": ">=22.0.0" },
  <% } else { %>
  "engines": { "node": ">=20.0.0" },
  <% } %>
  <% if (flavor === 'browser') { %>
  "private": true,
  <% } %>
  "scripts": {
    <% if (flavor === 'node' && lang === 'js') { %>
    "start": "node src/index.js"
    <% } else if (flavor === 'node' && lang === 'ts') { %>
    "dev": "tsc --watch",
    "build": "tsc",
    "start": "node dist/index.js"
    <% } else if (flavor === 'browser' && lang === 'js') { %>
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
    <% } else if (flavor === 'browser' && lang === 'ts') { %>
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
    <% } %>
  },
  <% if (flavor === 'node' && lang === 'ts') { %>
  "devDependencies": {
    "typescript": "^5.0.0",
    "@types/node": "^22.0.0"
  }
  <% } else if (flavor === 'browser' && lang === 'js') { %>
  "devDependencies": {
    "vite": "^6.0.0"
  }
  <% } else if (flavor === 'browser' && lang === 'ts') { %>
  "devDependencies": {
    "vite": "^6.0.0",
    "typescript": "^5.0.0"
  }
  <% } else { %>
  "dependencies": {}
  <% } %>
}