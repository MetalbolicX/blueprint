---
to: app/routes/<%= h.snakeCase(name) %>.py
---
from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel
from typing import Optional

router = APIRouter(prefix="/<%= h.kebabCase(name) %>", tags=["<%= name %>"])


class <%= name %>Create(BaseModel):
    """Request model for creating <%= name %>."""
    name: str
    description: Optional[str] = None


class <%= name %>Response(BaseModel):
    """Response model for <%= name %>."""
    id: str
    name: str
    description: Optional[str] = None


# In-memory storage for demo purposes
<%= h.snakeCase(name) %>_store: dict[str, <%= name %>Response] = {}


@router.get("/", response_model=list[<%= name %>Response])
async def list_<%= h.snakeCase(name) %>():
    """List all <%= name %> resources."""
    return list(<%= h.snakeCase(name) %>_store.values())


@router.get("/{<%= h.snakeCase(name) %>_id}", response_model=<%= name %>Response)
async def get_<%= h.snakeCase(name) %>(<%= h.snakeCase(name) %>_id: str):
    """Get a specific <%= name %> resource by ID."""
    if <%= h.snakeCase(name) %>_id not in <%= h.snakeCase(name) %>_store:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="<%= name %> not found"
        )
    return <%= h.snakeCase(name) %>_store[<%= h.snakeCase(name) %>_id]


@router.post("/", response_model=<%= name %>Response, status_code=status.HTTP_201_CREATED)
async def create_<%= h.snakeCase(name) %>(payload: <%= name %>Create):
    """Create a new <%= name %> resource."""
    import uuid
    new_id = str(uuid.uuid4())
    new_<%= h.snakeCase(name) %> = <%= name %>Response(
        id=new_id,
        name=payload.name,
        description=payload.description
    )
    <%= h.snakeCase(name) %>_store[new_id] = new_<%= h.snakeCase(name) %>
    return new_<%= h.snakeCase(name) %>


@router.delete("/{<%= h.snakeCase(name) %>_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_<%= h.snakeCase(name) %>(<%= h.snakeCase(name) %>_id: str):
    """Delete a <%= name %> resource."""
    if <%= h.snakeCase(name) %>_id not in <%= h.snakeCase(name) %>_store:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="<%= name %> not found"
        )
    del <%= h.snakeCase(name) %>_store[<%= h.snakeCase(name) %>_id]
    return None