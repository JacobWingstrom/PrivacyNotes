// hush-server is the optional self-hosted sync server for Hush.
//
// It stores only data that the apps have already encrypted with a key made from your
// sync passphrase, so the server (and anyone who gets into it) can't read your notes.
// See docs/sync-protocol.md for the wire format.
package main

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"

	bolt "go.etcd.io/bbolt"
)

const version = "1.0.0"

var (
	bRecords = []byte("records") // record id -> storedRecord JSON
	bSeq     = []byte("seq")     // big-endian seq -> record id
	bMeta    = []byte("meta")    // "vault" -> vault JSON, "head" -> uint64

	idPattern = regexp.MustCompile(`^[A-Za-z0-9_.-]{1,128}$`)
	blobIDRe  = regexp.MustCompile(`^[A-Za-z0-9_-]{8,128}$`)
)

const maxRecordBytes = 16 << 20 // one encrypted record, base64

type storedRecord struct {
	ID        string `json:"id"`
	Seq       uint64 `json:"seq"`
	Deleted   bool   `json:"deleted"`
	Data      string `json:"data,omitempty"`
	UpdatedAt int64  `json:"updatedAt"` // server time, unix milliseconds
}

type pushRecord struct {
	ID      string `json:"id"`
	Base    uint64 `json:"base"`
	Force   bool   `json:"force"`
	Deleted bool   `json:"deleted"`
	Data    string `json:"data"`
}

type pushResult struct {
	ID      string        `json:"id"`
	OK      bool          `json:"ok"`
	Seq     uint64        `json:"seq,omitempty"`
	Current *storedRecord `json:"current,omitempty"`
	Error   string        `json:"error,omitempty"`
}

type vaultInfo struct {
	Initialized bool   `json:"initialized"`
	Salt        string `json:"salt,omitempty"`
	Iterations  int    `json:"iterations,omitempty"`
	Check       string `json:"check,omitempty"`
	CreatedAt   int64  `json:"createdAt,omitempty"`
}

type server struct {
	db      *bolt.DB
	dataDir string
	token   string
	maxBlob int64
}

func main() {
	dataDir := env("HUSH_DATA", "/data")
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "token":
			t, err := loadOrCreateToken(dataDir)
			if err != nil {
				fmt.Fprintln(os.Stderr, err)
				os.Exit(1)
			}
			fmt.Println(t)
			return
		case "healthcheck":
			addr := env("HUSH_ADDR", ":8080")
			if strings.HasPrefix(addr, ":") {
				addr = "127.0.0.1" + addr
			}
			c := http.Client{Timeout: 4 * time.Second}
			resp, err := c.Get("http://" + addr + "/v1/health")
			if err != nil || resp.StatusCode != 200 {
				os.Exit(1)
			}
			return
		case "version":
			fmt.Println(version)
			return
		}
	}

	if err := os.MkdirAll(filepath.Join(dataDir, "blobs"), 0o700); err != nil {
		log.Fatalf("can't create data folder %s: %v", dataDir, err)
	}
	token, err := loadOrCreateToken(dataDir)
	if err != nil {
		log.Fatal(err)
	}
	s, err := openServer(dataDir, token)
	if err != nil {
		log.Fatal(err)
	}
	defer s.db.Close()
	if mb, err := strconv.Atoi(env("HUSH_MAX_BLOB_MB", "512")); err == nil && mb > 0 {
		s.maxBlob = int64(mb) << 20
	}

	addr := env("HUSH_ADDR", ":8080")
	srv := &http.Server{
		Addr:              addr,
		Handler:           logRequests(s.routes()),
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	log.Printf("Hush sync server %s listening on %s, data in %s", version, addr, dataDir)
	log.Printf("Pairing token: %s", token)
	log.Printf("(Show it again any time with: docker compose exec hush /hush-server token)")

	go func() {
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatal(err)
		}
	}()
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = srv.Shutdown(ctx)
	log.Print("stopped")
}

func env(key, def string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return def
}

// loadOrCreateToken uses HUSH_TOKEN if set, otherwise a random token saved in the data folder.
func loadOrCreateToken(dataDir string) (string, error) {
	if t := strings.TrimSpace(os.Getenv("HUSH_TOKEN")); t != "" {
		return t, nil
	}
	path := filepath.Join(dataDir, "token")
	if b, err := os.ReadFile(path); err == nil && len(strings.TrimSpace(string(b))) > 0 {
		return strings.TrimSpace(string(b)), nil
	}
	buf := make([]byte, 24)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	t := "hush_" + base64.RawURLEncoding.EncodeToString(buf)
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		return "", err
	}
	if err := os.WriteFile(path, []byte(t+"\n"), 0o600); err != nil {
		return "", fmt.Errorf("can't save token in %s: %w", dataDir, err)
	}
	return t, nil
}

func openServer(dataDir, token string) (*server, error) {
	if err := os.MkdirAll(filepath.Join(dataDir, "blobs"), 0o700); err != nil {
		return nil, err
	}
	db, err := bolt.Open(filepath.Join(dataDir, "hush.db"), 0o600, &bolt.Options{Timeout: 5 * time.Second})
	if err != nil {
		return nil, fmt.Errorf("can't open database: %w", err)
	}
	err = db.Update(func(tx *bolt.Tx) error {
		for _, b := range [][]byte{bRecords, bSeq, bMeta} {
			if _, err := tx.CreateBucketIfNotExists(b); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		db.Close()
		return nil, err
	}
	return &server{db: db, dataDir: dataDir, token: token, maxBlob: 512 << 20}, nil
}

func (s *server) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, 200, map[string]any{"ok": true, "app": "hush-server", "version": version, "protocol": 1})
	})
	mux.HandleFunc("GET /v1/vault", s.auth(s.getVault))
	mux.HandleFunc("PUT /v1/vault", s.auth(s.putVault))
	mux.HandleFunc("DELETE /v1/vault", s.auth(s.eraseVault))
	mux.HandleFunc("GET /v1/stats", s.auth(s.stats))
	mux.HandleFunc("GET /v1/system", s.auth(s.system))
	mux.HandleFunc("POST /v1/push", s.auth(s.push))
	mux.HandleFunc("GET /v1/pull", s.auth(s.pull))
	mux.HandleFunc("PUT /v1/blobs/{id}", s.auth(s.putBlob))
	mux.HandleFunc("GET /v1/blobs/{id}", s.auth(s.getBlob))
	mux.HandleFunc("HEAD /v1/blobs/{id}", s.auth(s.getBlob))
	mux.HandleFunc("DELETE /v1/blobs/{id}", s.auth(s.deleteBlob))
	mux.HandleFunc("GET /", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			writeErr(w, 404, "not found")
			return
		}
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		fmt.Fprintf(w, "Hush sync server %s is running.\nAdd this address in Hush: Settings > Sync.\n", version)
	})
	return mux
}

func (s *server) auth(next http.HandlerFunc) http.HandlerFunc {
	want := []byte("Bearer " + s.token)
	return func(w http.ResponseWriter, r *http.Request) {
		got := []byte(r.Header.Get("Authorization"))
		if subtle.ConstantTimeCompare(got, want) != 1 {
			writeErr(w, 401, "wrong or missing token")
			return
		}
		next(w, r)
	}
}

// MARK: vault

func (s *server) readVault(tx *bolt.Tx) vaultInfo {
	var v vaultInfo
	if b := tx.Bucket(bMeta).Get([]byte("vault")); b != nil {
		_ = json.Unmarshal(b, &v)
		v.Initialized = true
	}
	return v
}

func (s *server) getVault(w http.ResponseWriter, r *http.Request) {
	var v vaultInfo
	_ = s.db.View(func(tx *bolt.Tx) error { v = s.readVault(tx); return nil })
	writeJSON(w, 200, v)
}

func (s *server) putVault(w http.ResponseWriter, r *http.Request) {
	var v vaultInfo
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&v); err != nil {
		writeErr(w, 400, "bad vault JSON")
		return
	}
	if v.Salt == "" || v.Check == "" || v.Iterations < 10000 {
		writeErr(w, 400, "salt, check and iterations (>= 10000) are required")
		return
	}
	v.Initialized = true
	v.CreatedAt = time.Now().UnixMilli()
	replace := r.URL.Query().Get("replace") == "1"
	err := s.db.Update(func(tx *bolt.Tx) error {
		if s.readVault(tx).Initialized && !replace {
			return errConflict
		}
		b, _ := json.Marshal(v)
		return tx.Bucket(bMeta).Put([]byte("vault"), b)
	})
	if errors.Is(err, errConflict) {
		writeErr(w, 409, "this server already has a sync passphrase")
		return
	}
	if err != nil {
		writeErr(w, 500, err.Error())
		return
	}
	writeJSON(w, 200, v)
}

var errConflict = errors.New("conflict")

// eraseVault deletes every record, blob and the passphrase check. The token is kept.
func (s *server) eraseVault(w http.ResponseWriter, r *http.Request) {
	if r.URL.Query().Get("confirm") != "erase" {
		writeErr(w, 400, "add ?confirm=erase to erase everything on this server")
		return
	}
	err := s.db.Update(func(tx *bolt.Tx) error {
		for _, b := range [][]byte{bRecords, bSeq, bMeta} {
			if err := tx.DeleteBucket(b); err != nil {
				return err
			}
			if _, err := tx.CreateBucket(b); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		writeErr(w, 500, err.Error())
		return
	}
	dir := filepath.Join(s.dataDir, "blobs")
	_ = os.RemoveAll(dir)
	_ = os.MkdirAll(dir, 0o700)
	log.Print("all sync data erased")
	writeJSON(w, 200, map[string]any{"ok": true})
}

func (s *server) stats(w http.ResponseWriter, r *http.Request) {
	var records, deleted int
	var head uint64
	_ = s.db.View(func(tx *bolt.Tx) error {
		head = getHead(tx)
		return tx.Bucket(bRecords).ForEach(func(k, v []byte) error {
			var rec storedRecord
			if json.Unmarshal(v, &rec) == nil {
				if rec.Deleted {
					deleted++
				} else {
					records++
				}
			}
			return nil
		})
	})
	var blobs int
	var blobBytes int64
	entries, _ := os.ReadDir(filepath.Join(s.dataDir, "blobs"))
	for _, e := range entries {
		if info, err := e.Info(); err == nil && !e.IsDir() && !strings.HasPrefix(e.Name(), ".") {
			blobs++
			blobBytes += info.Size()
		}
	}
	writeJSON(w, 200, map[string]any{
		"records": records, "deleted": deleted, "head": head, "blobs": blobs, "blobBytes": blobBytes, "version": version,
	})
}

// MARK: records

func getHead(tx *bolt.Tx) uint64 {
	if b := tx.Bucket(bMeta).Get([]byte("head")); len(b) == 8 {
		return binary.BigEndian.Uint64(b)
	}
	return 0
}

func itob(v uint64) []byte {
	b := make([]byte, 8)
	binary.BigEndian.PutUint64(b, v)
	return b
}

func (s *server) push(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Records []pushRecord `json:"records"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<20)).Decode(&req); err != nil {
		writeErr(w, 400, "bad push JSON")
		return
	}
	if len(req.Records) > 1000 {
		writeErr(w, 400, "send at most 1000 records per push")
		return
	}
	results := make([]pushResult, 0, len(req.Records))
	var head uint64
	err := s.db.Update(func(tx *bolt.Tx) error {
		recs, seqs, meta := tx.Bucket(bRecords), tx.Bucket(bSeq), tx.Bucket(bMeta)
		head = getHead(tx)
		now := time.Now().UnixMilli()
		for _, in := range req.Records {
			if !idPattern.MatchString(in.ID) {
				results = append(results, pushResult{ID: in.ID, Error: "bad id"})
				continue
			}
			if !in.Deleted && (in.Data == "" || len(in.Data) > maxRecordBytes) {
				results = append(results, pushResult{ID: in.ID, Error: "data missing or too large"})
				continue
			}
			var existing *storedRecord
			if b := recs.Get([]byte(in.ID)); b != nil {
				var e storedRecord
				if json.Unmarshal(b, &e) == nil {
					existing = &e
				}
			}
			// Someone else changed this record since the client last saw it.
			if existing != nil && !in.Force && existing.Seq != in.Base {
				cur := *existing
				results = append(results, pushResult{ID: in.ID, Current: &cur})
				continue
			}
			if existing != nil {
				if err := seqs.Delete(itob(existing.Seq)); err != nil {
					return err
				}
			}
			head++
			rec := storedRecord{ID: in.ID, Seq: head, Deleted: in.Deleted, UpdatedAt: now}
			if !in.Deleted {
				rec.Data = in.Data
			}
			b, _ := json.Marshal(rec)
			if err := recs.Put([]byte(in.ID), b); err != nil {
				return err
			}
			if err := seqs.Put(itob(head), []byte(in.ID)); err != nil {
				return err
			}
			results = append(results, pushResult{ID: in.ID, OK: true, Seq: head})
		}
		return meta.Put([]byte("head"), itob(head))
	})
	if err != nil {
		writeErr(w, 500, err.Error())
		return
	}
	writeJSON(w, 200, map[string]any{"results": results, "head": head})
}

func (s *server) pull(w http.ResponseWriter, r *http.Request) {
	since, _ := strconv.ParseUint(r.URL.Query().Get("since"), 10, 64)
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 || limit > 1000 {
		limit = 500
	}
	maxBytes := 24 << 20
	out := []storedRecord{}
	var head, last uint64
	more := false
	_ = s.db.View(func(tx *bolt.Tx) error {
		head = getHead(tx)
		last = since
		recs := tx.Bucket(bRecords)
		c := tx.Bucket(bSeq).Cursor()
		size := 0
		for k, v := c.Seek(itob(since + 1)); k != nil; k, v = c.Next() {
			if len(out) >= limit || size > maxBytes {
				more = true
				break
			}
			var rec storedRecord
			if b := recs.Get(v); b != nil && json.Unmarshal(b, &rec) == nil {
				out = append(out, rec)
				size += len(rec.Data)
			}
			last = binary.BigEndian.Uint64(k)
		}
		return nil
	})
	writeJSON(w, 200, map[string]any{"records": out, "seq": last, "head": head, "more": more})
}

// MARK: blobs (encrypted attachments)

func (s *server) blobPath(w http.ResponseWriter, r *http.Request) (string, bool) {
	id := r.PathValue("id")
	if !blobIDRe.MatchString(id) {
		writeErr(w, 400, "bad blob id")
		return "", false
	}
	return filepath.Join(s.dataDir, "blobs", id), true
}

func (s *server) putBlob(w http.ResponseWriter, r *http.Request) {
	path, ok := s.blobPath(w, r)
	if !ok {
		return
	}
	tmp, err := os.CreateTemp(filepath.Join(s.dataDir, "blobs"), ".upload-*")
	if err != nil {
		writeErr(w, 500, err.Error())
		return
	}
	defer os.Remove(tmp.Name())
	n, err := io.Copy(tmp, http.MaxBytesReader(w, r.Body, s.maxBlob))
	if cerr := tmp.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		writeErr(w, 413, "upload failed or too large: "+err.Error())
		return
	}
	if err := os.Rename(tmp.Name(), path); err != nil {
		writeErr(w, 500, err.Error())
		return
	}
	writeJSON(w, 200, map[string]any{"ok": true, "size": n})
}

func (s *server) getBlob(w http.ResponseWriter, r *http.Request) {
	path, ok := s.blobPath(w, r)
	if !ok {
		return
	}
	f, err := os.Open(path)
	if err != nil {
		writeErr(w, 404, "no such blob")
		return
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		writeErr(w, 500, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/octet-stream")
	http.ServeContent(w, r, "", info.ModTime(), f)
}

func (s *server) deleteBlob(w http.ResponseWriter, r *http.Request) {
	path, ok := s.blobPath(w, r)
	if !ok {
		return
	}
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		writeErr(w, 500, err.Error())
		return
	}
	writeJSON(w, 200, map[string]any{"ok": true})
}

// MARK: helpers

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, map[string]any{"error": msg})
}

type statusWriter struct {
	http.ResponseWriter
	code int
}

func (s *statusWriter) WriteHeader(c int) { s.code = c; s.ResponseWriter.WriteHeader(c) }

// logRequests logs method, path and status only; never bodies or tokens.
func logRequests(h http.Handler) http.Handler {
	quiet := env("HUSH_LOG", "") == "quiet"
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, code: 200}
		h.ServeHTTP(sw, r)
		if quiet || r.URL.Path == "/v1/health" {
			return
		}
		log.Printf("%s %s %d %s", r.Method, r.URL.Path, sw.code, time.Since(start).Round(time.Millisecond))
	})
}
