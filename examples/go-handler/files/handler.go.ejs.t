---
to: <%= package %>/<%= h.snakeCase(name) %>.go
---
package <%= package %>

import (
	"encoding/json"
	"net/http"
)

// <%= name %>Handler handles HTTP requests for <%= name %> resources.
type <%= name %>Handler struct {
	// Add dependencies here (e.g., database, logger)
}

// New<%= name %>Handler creates a new <%= name %>Handler instance.
func New<%= name %>Handler() *<%= name %>Handler {
	return &<%= name %>Handler{}
}

// ServeHTTP handles HTTP requests.
// @Summary <%= name %> endpoint
// @Description Handles GET and POST requests for <%= name %> resources
// @Tags <%= name %>
// @Accept json
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Failure 500 {object} map[string]string
// @Router /<%= h.kebabCase(name) %> [get]
func (h *<%= name %>Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		h.get<%= name %>(w, r)
	case http.MethodPost:
		h.post<%= name %>(w, r)
	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}

func (h *<%= name %>Handler) get<%= name %>(w http.ResponseWriter, r *http.Request) {
	response := map[string]interface{}{
		"message": "<%= name %> resource",
		"items":    []string{},
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func (h *<%= name %>Handler) post<%= name %>(w http.ResponseWriter, r *http.Request) {
	var data map[string]interface{}

	if err := json.NewDecoder(r.Body).Decode(&data); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	response := map[string]interface{}{
		"message": "<%= name %> created",
		"data":    data,
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(response)
}