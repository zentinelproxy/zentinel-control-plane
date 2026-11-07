package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"path"
	"strings"

	"github.com/klauspost/compress/zstd"
)

const maxExtractedBytes = 512 << 20

// verifyBundle checks the archive against the checksum and, when a public key is
// configured, the signature. The control plane signs the archive bytes.
func verifyBundle(archive []byte, checksum, signature string, pub ed25519.PublicKey, requireSignature bool) error {
	sum := sha256.Sum256(archive)
	if !strings.EqualFold(hex.EncodeToString(sum[:]), checksum) {
		return fmt.Errorf("checksum mismatch")
	}

	if signature == "" {
		if requireSignature {
			return fmt.Errorf("bundle is not signed")
		}
		return nil
	}
	if pub == nil {
		return nil
	}
	sig, err := base64.StdEncoding.DecodeString(signature)
	if err != nil {
		return fmt.Errorf("signature is not Base64")
	}
	if !ed25519.Verify(pub, archive, sig) {
		return fmt.Errorf("signature does not verify")
	}
	return nil
}

// extractBundle returns the files in a bundle archive, which is a tar file,
// optionally zstd or gzip compressed. Paths that could escape the target
// directory, links and other special files are rejected.
func extractBundle(archive []byte) (map[string][]byte, error) {
	r, err := decompress(archive)
	if err != nil {
		return nil, err
	}

	files := map[string][]byte{}
	var total int64
	tr := tar.NewReader(r)
	for {
		hdr, err := tr.Next()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("reading archive: %w", err)
		}
		switch hdr.Typeflag {
		case tar.TypeDir:
			continue
		case tar.TypeReg:
		default:
			return nil, fmt.Errorf("archive entry %q is not a regular file", hdr.Name)
		}
		name, err := safePath(hdr.Name)
		if err != nil {
			return nil, err
		}
		total += hdr.Size
		if total > maxExtractedBytes {
			return nil, fmt.Errorf("archive expands beyond %d bytes", maxExtractedBytes)
		}
		data, err := io.ReadAll(io.LimitReader(tr, hdr.Size))
		if err != nil {
			return nil, err
		}
		files[name] = data
	}

	if _, ok := files["zentinel.kdl"]; !ok {
		return nil, fmt.Errorf("archive has no zentinel.kdl")
	}
	if err := checkManifest(files); err != nil {
		return nil, err
	}
	return files, nil
}

func decompress(archive []byte) (io.Reader, error) {
	switch {
	case bytes.HasPrefix(archive, []byte{0x28, 0xb5, 0x2f, 0xfd}):
		dec, err := zstd.NewReader(bytes.NewReader(archive), zstd.WithDecoderMaxMemory(maxExtractedBytes))
		if err != nil {
			return nil, err
		}
		return dec.IOReadCloser(), nil
	case bytes.HasPrefix(archive, []byte{0x1f, 0x8b}):
		return gzip.NewReader(bytes.NewReader(archive))
	default:
		return bytes.NewReader(archive), nil
	}
}

func safePath(name string) (string, error) {
	clean := path.Clean(strings.TrimPrefix(name, "./"))
	if name == "" || path.IsAbs(name) || clean == "." || clean == ".." || strings.HasPrefix(clean, "../") || strings.Contains(name, "\\") {
		return "", fmt.Errorf("archive entry %q has an unsafe path", name)
	}
	return clean, nil
}

// checkManifest compares each file with its checksum in manifest.json.
func checkManifest(files map[string][]byte) error {
	raw, ok := files["manifest.json"]
	if !ok {
		return nil
	}
	var manifest struct {
		Files []struct {
			Path     string `json:"path"`
			Checksum string `json:"checksum"`
		} `json:"files"`
	}
	if err := json.Unmarshal(raw, &manifest); err != nil {
		return fmt.Errorf("manifest.json is not valid: %w", err)
	}
	for _, f := range manifest.Files {
		name, err := safePath(f.Path)
		if err != nil {
			return err
		}
		data, ok := files[name]
		if !ok {
			return fmt.Errorf("manifest lists %q, which is not in the archive", f.Path)
		}
		sum := sha256.Sum256(data)
		if !strings.EqualFold(hex.EncodeToString(sum[:]), f.Checksum) {
			return fmt.Errorf("checksum mismatch for %q", f.Path)
		}
	}
	return nil
}
