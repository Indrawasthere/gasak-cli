package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"
)

const (
	VaultPort = 9002
	LogFile   = "vault_server.log"
)

type SecretPayload struct {
	GLPIUrl         string `json:"GLPI_URL"`
	OutlineURL      string `json:"OUTLINE_URL"`
	OutlineAPIKey   string `json:"OUTLINE_API_KEY"`
	LinearAPIKey    string `json:"LINEAR_API_KEY"`
	SshUser         string `json:"PARKEE_SSH_USER"`
	SshPass         string `json:"PARKEE_SSH_PASS"`
	CmsDbHost       string `json:"CMS_DB_HOST"`
	CmsDbPort       string `json:"CMS_DB_PORT"`
	CmsDbUser       string `json:"CMS_DB_USER"`
	CmsDbPass       string `json:"CMS_DB_PASS"`
	CmsDbName       string `json:"CMS_DB_NAME"`
	GsheetDeployId  string `json:"GSHEET_DEPLOY_ID"`
	GsheetDeployGid string `json:"GSHEET_DEPLOY_GID"`
}

type ClientRequest struct {
	Token     string `json:"token"`
	PublicKey string `json:"public_key"`
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
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	var req ClientRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	if req.Token != "gsk_dist_9f2k7x" {
		w.WriteHeader(http.StatusUnauthorized)
		logAccess(r, http.StatusUnauthorized, "Token distribusi tidak valid")
		return
	}

	// Sanitize string public key kiriman client
	pubKeyStr := req.PublicKey
	pubKeyStr = strings.ReplaceAll(pubKeyStr, `\n`, "\n")
	pubKeyStr = strings.TrimSpace(pubKeyStr)

	// Jika client cuma ngirim raw string base64 tanpa header PEM
	if !strings.Contains(pubKeyStr, "BEGIN PUBLIC KEY") {
		pubKeyStr = fmt.Sprintf("-----BEGIN PUBLIC KEY-----\n%s\n-----END PUBLIC KEY-----", pubKeyStr)
	}

	secrets := SecretPayload{
		GLPIUrl:         os.Getenv("GLPI_URL"),
		OutlineURL:      os.Getenv("OUTLINE_URL"),
		OutlineAPIKey:   os.Getenv("OUTLINE_API_KEY"),
		LinearAPIKey:    os.Getenv("LINEAR_API_KEY"),
		SshUser:         os.Getenv("PARKEE_SSH_USER"),
		SshPass:         os.Getenv("PARKEE_SSH_PASS"),
		CmsDbHost:       os.Getenv("CMS_DB_HOST"),
		CmsDbPort:       os.Getenv("CMS_DB_PORT"),
		CmsDbUser:       os.Getenv("CMS_DB_USER"),
		CmsDbPass:       os.Getenv("CMS_DB_PASS"),
		CmsDbName:       os.Getenv("CMS_DB_NAME"),
		GsheetDeployId:  os.Getenv("GSHEET_DEPLOY_ID"),
		GsheetDeployGid: os.Getenv("GSHEET_DEPLOY_GID"),
	}

	plaintext, err := json.Marshal(secrets)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	outbound, err := encryptHybrid(plaintext, pubKeyStr)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"error":"` + err.Error() + `"}`))
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(outbound)
}

func encryptHybrid(plaintext []byte, pubKeyPEM string) (*OutboundVault, error) {
	// Menjamin format string multiline PEM bersih total
	pubKeyPEM = strings.ReplaceAll(pubKeyPEM, `\n`, "\n")
	pubKeyPEM = strings.TrimSpace(pubKeyPEM)

	block, _ := pem.Decode([]byte(pubKeyPEM))
	if block == nil {
		return nil, fmt.Errorf("failed to decode public key PEM (block empty)")
	}

	pub, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("failed to parse public key bytes: %w", err)
	}

	rsaPubKey, ok := pub.(*rsa.PublicKey)
	if !ok {
		return nil, fmt.Errorf("bukan RSA Public Key")
	}

	// 1. Generate AES 256 Key
	aesKey := make([]byte, 32)
	if _, err := rand.Read(aesKey); err != nil {
		return nil, err
	}

	aesBlock, err := aes.NewCipher(aesKey)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(aesBlock)
	if err != nil {
		return nil, err
	}

	// 2. Generate Nonce
	nonce := make([]byte, gcm.NonceSize())
	if _, err = rand.Read(nonce); err != nil {
		return nil, err
	}

	// 3. Encrypt Payload menggunakan AES-GCM
	ciphertext := gcm.Seal(nil, nonce, plaintext, nil)

	// 4. Encrypt AES Key menggunakan RSA-OAEP Public Key Client
	encryptedKey, err := rsa.EncryptOAEP(sha256.New(), rand.Reader, rsaPubKey, aesKey, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to envelope key via RSA-OAEP: %w", err)
	}

	return &OutboundVault{
		EncryptedKey: hex.EncodeToString(encryptedKey),
		Payload:      hex.EncodeToString(ciphertext),
		Nonce:        hex.EncodeToString(nonce),
	}, nil
}

func handleLocateGate(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	token := r.Header.Get("X-Gasak-Token")
	if token != "gsk_dist_9f2k7x" {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"error": "Unauthorized",
		})
		return
	}

	keyword := strings.ToLower(r.URL.Query().Get("keyword"))
	if keyword == "" {
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	gates, err := queryGateViaTeleport(keyword)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"error": err.Error(),
		})
		return
	}

	_ = json.NewEncoder(w).Encode(gates)
}

func queryGateViaTeleport(keyword string) ([]LocateResponse, error) {
	cleanKeyword := strings.TrimSpace(strings.ToLower(keyword))

	nodeName := "server-" + cleanKeyword
	dbName := "agent_" + cleanKeyword

	query := `
SELECT DISTINCT ON(user_pc)
    user_pc,
    ip_address
FROM core_user_activity
WHERE lower(user_pc) LIKE '%' || (SELECT lower(unique_code) FROM location) || '%'
  AND deleted_at IS NULL
  AND action_type = 'LOGIN'
  AND created_at >= NOW() - INTERVAL '30 days'
ORDER BY user_pc, created_at DESC;
`

	query = strings.ReplaceAll(query, "\n", " ")
	query = strings.ReplaceAll(query, "\t", " ")

	cmdStr := fmt.Sprintf(
		`psql -h localhost -d %s -U agent -At -F '|' -c "%s"`,
		dbName,
		query,
	)

	cmd := exec.Command(
		"tsh",
		"ssh",
		fmt.Sprintf("server@%s", nodeName),
		cmdStr,
	)

	output, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("teleport query failed: %v | %s", err, string(output))
	}

	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	var gates []LocateResponse

	for _, line := range lines {
		cleanedLine := strings.TrimSpace(line)
		if cleanedLine == "" {
			continue
		}

		parts := strings.Split(cleanedLine, "|")
		if len(parts) != 2 {
			continue
		}

		gates = append(gates, LocateResponse{
			NamaLokasi: parts[0],
			IPAddress:  parts[1],
		})
	}

	return gates, nil
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
