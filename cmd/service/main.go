package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"
)

type healthResponse struct {
	OK      bool   `json:"ok"`
	Service string `json:"service"`
	Time    string `json:"time"`
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "9080"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /", rootHandler)
	mux.HandleFunc("GET /healthz", healthHandler)

	addr := ":" + port
	log.Printf("windpipe service listening on http://localhost%s", addr)

	server := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
}

func rootHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	_, _ = w.Write([]byte("windpipe service is running\n"))
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(healthResponse{
		OK:      true,
		Service: "windpipe",
		Time:    time.Now().UTC().Format(time.RFC3339),
	})
}
