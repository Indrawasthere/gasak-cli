package main

// ─────────────────────────────────────────────────────────────
// GASAK VAULT SERVER — HYBRID SECURITY ENGINE
// Port: 9002 di Server Supeng
// Menerima Public Key Client via HTTP, Melakukan Hybrid Encryption
// Dan Menyediakan Endpoint API Terpusat untuk Ambil Log Agent
// ─────────────────────────────────────────────────────────────

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	_ "github.com/lib/pq" // Driver PostgreSQL untuk koneksi DB pusat
)

const (
	VaultPort = 9002
	LogFile   = "vault_server.log"
)

type SecretPayload struct {
	GLPIUrl       string `json:"GLPI_URL"`
	OutlineURL    string `json:"OUTLINE_URL"`
	OutlineAPIKey string `json:"OUTLINE_API_KEY"`
	LinearAPIKey  string `json:"LINEAR_API_KEY"`
	SshUser       string `json:"PARKEE_SSH_USER"`
	SshPass       string `json:"PARKEE_SSH_PASS"`
	CmsDbHost     string `json:"CMS_DB_HOST"`
	CmsDbPort     string `json:"CMS_DB_PORT"`
	CmsDbUser     string `json:"CMS_DB_USER"`
	CmsDbPass     string `json:"CMS_DB_PASS"`
	CmsDbName     string `json:"CMS_DB_NAME"`
}

type ClientRequest struct {
	Token     string `json:"token"`
	PublicKey string `json:"public_key"` // PEM string dari client
}

type OutboundVault struct {
	EncryptedKey string `json:"encrypted_key"`
	Payload      string `json:"payload"`
	Nonce        string `json:"nonce"`
}

type LocateResponse struct {
	NamaLokasi string `json:"nama_lokasi"`
	IPAddress  string `json:"ip_address"`
}

func main() {
	_ = os.WriteFile(LogFile, []byte(""), 0644)
	log.Printf("[INIT] GASAK Vault Server berjalan pada port :%d", VaultPort)

	http.HandleFunc("/getenv", handleGetEnv)
	http.HandleFunc("/health", handleHealth)
	http.HandleFunc("/api/locate-gate", handleLocateGate)

	err := http.ListenAndServe(fmt.Sprintf(":%d", VaultPort), nil)
	if err != nil {
		log.Fatalf("[FATAL] Gagal menjalankan server: %v", err)
	}
}

func handleGetEnv(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		logAccess(r, 452, "INVALID METHOD")
		return
	}

	var req ClientRequest
	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "Bad Request", http.StatusBadRequest)
		return
	}

	if err := json.Unmarshal(body, &req); err != nil {
		http.Error(w, "Invalid JSON structure", http.StatusBadRequest)
		logAccess(r, 400, "BAD JSON")
		return
	}

	// Validasi Token Distribusi
	expectedToken := os.Getenv("GASAK_DIST_TOKEN")
	if expectedToken == "" || req.Token != expectedToken {
		http.Error(w, "Forbidden: Token Mismatch", http.StatusForbidden)
		logAccess(r, 403, "TOKEN MISMATCH")
		return
	}

	if req.PublicKey == "" {
		http.Error(w, "Bad Request: Missing Public Key", http.StatusBadRequest)
		logAccess(r, 400, "MISSING PUBKEY")
		return
	}

	// Load secrets dari env server
	secrets := SecretPayload{
		GLPIUrl:       os.Getenv("GLPI_URL"),
		OutlineURL:    os.Getenv("OUTLINE_URL"),
		OutlineAPIKey: os.Getenv("OUTLINE_API_KEY"),
		LinearAPIKey:  os.Getenv("LINEAR_API_KEY"),
		SshUser:       os.Getenv("PARKEE_SSH_USER"),
		SshPass:       os.Getenv("PARKEE_SSH_PASS"),
		CmsDbHost:     os.Getenv("CMS_DB_HOST"),
		CmsDbPort:     getEnvDefault("CMS_DB_PORT", "5432"),
		CmsDbUser:     os.Getenv("CMS_DB_USER"),
		CmsDbPass:     os.Getenv("CMS_DB_PASS"),
		CmsDbName:     os.Getenv("CMS_DB_NAME"),
	}

	plaintext, _ := json.Marshal(secrets)

	// Lakukan Enkripsi Hybrid menggunakan Public Key Client
	vaultData, err := encryptHybrid(plaintext, req.PublicKey)
	if err != nil {
		http.Error(w, "Internal Server Error: Encryption Failed", http.StatusInternalServerError)
		logAccess(r, 500, "CRYPTO ERROR: "+err.Error())
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(vaultData)
	logAccess(r, 200, "VAULT COMPILED & DISPATCHED ASYMMETRICALLY")
}

func encryptHybrid(plaintext []byte, pubKeyPEM string) (*OutboundVault, error) {
	// SANITIZER: Ubah teks literal "\n" menjadi byte newline asli (\n)
	pubKeyPEM = strings.ReplaceAll(pubKeyPEM, `\n`, "\n")
	pubKeyPEM = strings.TrimSpace(pubKeyPEM)

	block, _ := pem.Decode([]byte(pubKeyPEM))
	if block == nil {
		return nil, fmt.Errorf("failed to decode public key PEM")
	}

	pub, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("failed to parse public key: %w", err)
	}

	rsaPubKey, ok := pub.(*rsa.PublicKey)
	if !ok {
		return nil, fmt.Errorf("bukan RSA Public Key")
	}

	// 1. Generate Ephemeral 32-byte AES Key secara acak
	aesKey := make([]byte, 32)
	if _, err := rand.Read(aesKey); err != nil {
		return nil, err
	}

	// 2. Encrypt Payload menggunakan AES-256-GCM (Symmetric)
	aesBlock, err := aes.NewCipher(aesKey)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(aesBlock)
	if err != nil {
		return nil, err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err = rand.Read(nonce); err != nil {
		return nil, err
	}
	ciphertext := gcm.Seal(nil, nonce, plaintext, nil)

	// 3. Bungkus AES Key menggunakan RSA Public Key Client (Asymmetric)
	encryptedKey, err := rsa.EncryptOAEP(sha256.New(), rand.Reader, rsaPubKey, aesKey, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to envelope key: %w", err)
	}

	return &OutboundVault{\n\t\tEncryptedKey: hex.EncodeToString(encryptedKey),
		Payload:      hex.EncodeToString(ciphertext),
		Nonce:        hex.EncodeToString(nonce),
	}, nil
}

func handleLocateGate(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// Validasi token distribusi sederhana biar ga sembarang orang nembak query
	token := r.Header.Get("X-Gasak-Token")
	if token != "gsk_dist_9f2k7x" {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": "Unauthorized men!"})
		logAccess(r, 401, "UNAUTHORIZED GATE LOCATE REQUEST")
		return
	}

	keyword := r.URL.Query().Get("keyword")
	if keyword == "" {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": "Butuh parameter keyword lokasi!"})
		return
	}

	// Load DB config server pusat langsung dari system env server
	dbHost := os.Getenv("CMS_DB_HOST")
	dbPort := os.Getenv("CMS_DB_PORT")
	dbUser := os.Getenv("CMS_DB_USER")
	dbPass := os.Getenv("CMS_DB_PASS")
	dbName := os.Getenv("CMS_DB_NAME")

	if dbPort == "" {
		dbPort = "5432"
	}

	dsn := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable", dbHost, dbPort, dbUser, dbPass, dbName)
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": "Gagal konek DB pusat: " + err.Error()})
		logAccess(r, 500, "DB CONN ERROR: "+err.Error())
		return
	}
	defer db.Close()

	// Query pencarian data aktivitas login dari user
	query := `
		SELECT DISTINCT ON (user_pc)
			user_pc AS nama_lokasi,
			(
				SELECT trim(ip)
				FROM unnest(string_to_array(ip_address, ' ')) AS ip
				WHERE ip LIKE '10.70.%'
				LIMIT 1
			) AS ip_address,
			created_at AS last_seen
		FROM (
			SELECT user_pc, ip_address, created_at
			FROM core_user_activity
			WHERE lower(user_pc) LIKE $1
			  AND deleted_at IS NULL
			  AND action_type = 'LOGIN'
			  AND created_at >= NOW() - INTERVAL '31 days'
		) AS get_data
		ORDER BY user_pc, created_at DESC LIMIT 1;`

	var resp LocateResponse
	var lastSeen time.Time

	// Cari wildcard match query
	searchTerm := "%" + strings.ToLower(keyword) + "%"
	err = db.QueryRow(query, searchTerm).Scan(&resp.NamaLokasi, &resp.IPAddress, &lastSeen)
	if err != nil {
		w.WriteHeader(http.StatusNotFound)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": "Lokasi tidak ditemukan atau data activity kosong 31 hari terakhir."})
		logAccess(r, 404, "LOKASI TIDAK KETEMU: "+keyword)
		return
	}

	_ = json.NewEncoder(w).Encode(resp)
	logAccess(r, 200, "GATE LOCATED SUCCESSFULLY: "+resp.NamaLokasi)
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "ok", "time": time.Now().Format(time.RFC3339)})
}

func logAccess(r *http.Request, status int, msg string) {
	ip := r.RemoteAddr
	if idx := strings.LastIndex(ip, ":"); idx != -1 {
		ip = ip[:idx]
	}
	logStr := fmt.Sprintf("[%s] %s | %d | %s\n", time.Now().Format("2006-01-02 15:04:05"), ip, status, msg)
	fmt.Print(logStr)
	f, err := os.OpenFile(LogFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err == nil {
		defer f.Close()
		_, _ = f.WriteString(logStr)
	}
}

func getEnvDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
