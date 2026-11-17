package main

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func newTestServer(t *testing.T) (*httptest.Server, func(method, path string, body any) (int, map[string]any)) {
	t.Helper()
	s, err := openServer(t.TempDir(), "secret")
	if err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(s.routes())
	t.Cleanup(func() { ts.Close(); s.db.Close() })
	call := func(method, path string, body any) (int, map[string]any) {
		var rd io.Reader
		switch b := body.(type) {
		case nil:
		case []byte:
			rd = bytes.NewReader(b)
		default:
			j, _ := json.Marshal(b)
			rd = bytes.NewReader(j)
		}
		req, _ := http.NewRequest(method, ts.URL+path, rd)
		req.Header.Set("Authorization", "Bearer secret")
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		out := map[string]any{}
		raw, _ := io.ReadAll(resp.Body)
		_ = json.Unmarshal(raw, &out)
		if len(out) == 0 {
			out["raw"] = string(raw)
		}
		return resp.StatusCode, out
	}
	return ts, call
}

func TestAuth(t *testing.T) {
	ts, _ := newTestServer(t)
	resp, _ := http.Get(ts.URL + "/v1/health")
	if resp.StatusCode != 200 {
		t.Fatalf("health should be open, got %d", resp.StatusCode)
	}
	resp, _ = http.Get(ts.URL + "/v1/pull")
	if resp.StatusCode != 401 {
		t.Fatalf("pull without token should be 401, got %d", resp.StatusCode)
	}
}

func TestVault(t *testing.T) {
	_, call := newTestServer(t)
	code, v := call("GET", "/v1/vault", nil)
	if code != 200 || v["initialized"] != false {
		t.Fatalf("fresh vault: %d %v", code, v)
	}
	vault := map[string]any{"salt": "c2FsdA==", "iterations": 600000, "check": "Y2hlY2s="}
	if code, _ := call("PUT", "/v1/vault", vault); code != 200 {
		t.Fatalf("put vault: %d", code)
	}
	if code, _ := call("PUT", "/v1/vault", vault); code != 409 {
		t.Fatalf("second put should conflict, got %d", code)
	}
	code, v = call("GET", "/v1/vault", nil)
	if v["initialized"] != true || v["salt"] != "c2FsdA==" {
		t.Fatalf("vault after put: %v", v)
	}
}

func TestPushPullConflict(t *testing.T) {
	_, call := newTestServer(t)
	push := func(recs ...map[string]any) []any {
		code, out := call("POST", "/v1/push", map[string]any{"records": recs})
		if code != 200 {
			t.Fatalf("push: %d %v", code, out)
		}
		return out["results"].([]any)
	}
	r := push(map[string]any{"id": "a", "base": 0, "data": "AAAA"}, map[string]any{"id": "b", "base": 0, "data": "BBBB"})
	if r[0].(map[string]any)["ok"] != true || r[1].(map[string]any)["seq"].(float64) != 2 {
		t.Fatalf("first push: %v", r)
	}
	// Updating "a" from a stale base is a conflict and returns the current copy.
	r = push(map[string]any{"id": "a", "base": 0, "data": "CCCC"})
	res := r[0].(map[string]any)
	if res["ok"] == true || res["current"].(map[string]any)["data"] != "AAAA" {
		t.Fatalf("expected conflict: %v", res)
	}
	// Same update with the right base wins.
	r = push(map[string]any{"id": "a", "base": 1, "data": "CCCC"})
	if r[0].(map[string]any)["seq"].(float64) != 3 {
		t.Fatalf("update: %v", r)
	}
	// Delete b.
	push(map[string]any{"id": "b", "base": 2, "deleted": true})

	_, out := call("GET", "/v1/pull?since=0", nil)
	recs := out["records"].([]any)
	if len(recs) != 2 || out["seq"].(float64) != 4 {
		t.Fatalf("pull since 0: %v", out)
	}
	if recs[0].(map[string]any)["id"] != "a" || recs[1].(map[string]any)["deleted"] != true {
		t.Fatalf("pull order: %v", recs)
	}
	_, out = call("GET", "/v1/pull?since=3", nil)
	if n := len(out["records"].([]any)); n != 1 {
		t.Fatalf("pull since 3 should return 1, got %d", n)
	}
	_, out = call("GET", "/v1/pull?since=1&limit=1", nil)
	if out["more"] != true {
		t.Fatalf("limit should report more: %v", out)
	}
}

func TestBlobs(t *testing.T) {
	_, call := newTestServer(t)
	if code, _ := call("PUT", "/v1/blobs/blob-12345", []byte("encrypted bytes")); code != 200 {
		t.Fatalf("put blob: %d", code)
	}
	code, out := call("GET", "/v1/blobs/blob-12345", nil)
	if code != 200 || out["raw"] != "encrypted bytes" {
		t.Fatalf("get blob: %d %v", code, out)
	}
	if code, _ := call("PUT", "/v1/blobs/..%2F..%2Fetc", []byte("x")); code == 200 {
		t.Fatal("path traversal must be rejected")
	}
	call("DELETE", "/v1/blobs/blob-12345", nil)
	if code, _ := call("GET", "/v1/blobs/blob-12345", nil); code != 404 {
		t.Fatalf("deleted blob should 404, got %d", code)
	}
}

func TestErase(t *testing.T) {
	_, call := newTestServer(t)
	call("PUT", "/v1/vault", map[string]any{"salt": "c2FsdA==", "iterations": 600000, "check": "Y2hlY2s="})
	call("POST", "/v1/push", map[string]any{"records": []any{map[string]any{"id": "a", "data": "AAAA"}}})
	call("PUT", "/v1/blobs/blob-12345", []byte("x"))
	if code, _ := call("DELETE", "/v1/vault", nil); code != 400 {
		t.Fatal("erase must need confirm")
	}
	if code, _ := call("DELETE", "/v1/vault?confirm=erase", nil); code != 200 {
		t.Fatal("erase failed")
	}
	_, v := call("GET", "/v1/vault", nil)
	_, p := call("GET", "/v1/pull", nil)
	_, st := call("GET", "/v1/stats", nil)
	if v["initialized"] != false || len(p["records"].([]any)) != 0 || st["blobs"].(float64) != 0 {
		t.Fatalf("not erased: %v %v %v", v, p, st)
	}
	if !strings.Contains(st["version"].(string), ".") {
		t.Fatal("stats should include version")
	}
}

func TestSystemStats(t *testing.T) {
	info := collectSystem(t.TempDir(), "", "/proc", "/sys")
	if info.Cores < 1 || info.MemTotal == 0 || info.MemUsed > info.MemTotal {
		t.Fatalf("bad system info: %+v", info)
	}
	if len(info.Disks) == 0 || info.Disks[0].Used > info.Disks[0].Total {
		t.Fatalf("no data disk: %+v", info.Disks)
	}
	if info.CPUPercent < 0 || info.CPUPercent > 100 || len(info.Load) != 3 {
		t.Fatalf("bad cpu/load: %+v", info)
	}
}
