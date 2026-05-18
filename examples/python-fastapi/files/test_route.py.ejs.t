---
to: app/routes/<%= h.snakeCase(name) %>_test.py
---
import pytest
from fastapi.testclient import TestClient
from <%= h.snakeCase(name) %> import router

# Create a test client for the router
# Note: Adjust import path based on your project structure


class Test<%= name %>:
    """Tests for <%= name %> route."""

    def test_list_empty(self):
        """Test listing resources when store is empty."""
        # When store is empty, returns empty list
        pass

    def test_create(self):
        """Test creating a new resource."""
        payload = {
            "name": "<%= name %>",
            "description": "<%= description %>"
        }
        # POST to / creates new resource with id
        pass

    def test_create_requires_name(self):
        """Test that creating requires a name field."""
        payload = {"description": "No name provided"}
        # Should return 422 validation error
        pass

    def test_get_not_found(self):
        """Test getting a non-existent resource returns 404."""
        fake_id = "00000000-0000-0000-0000-000000000000"
        # GET /{fake_id} should return 404
        pass

    def test_delete_not_found(self):
        """Test deleting a non-existent resource returns 404."""
        fake_id = "00000000-0000-0000-0000-000000000000"
        # DELETE /{fake_id} should return 404
        pass