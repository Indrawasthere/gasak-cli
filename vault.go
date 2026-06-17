package main

// ─────────────────────────────────────────────────────────────
// GASAK LOCAL VAULT — HYBRID ASYMMETRIC EDITION
// Gak pake machine-id. Pake RSA Keypair internal khusus GASAK.
// ─────────────────────────────────────────────────────────────

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
	"os"
	"path/filepath"
)

const (
	VaultDir       = ".config/gasak"
	VaultFile      = "vault"
	PrivateKeyFile = "id_rsa"
	PublicKeyFile  = "id_rsa.pub"
)

// VaultData — Struktur bungkusan ciphertext dari server
type VaultData struct {
	EncryptedKey string `json:"encrypted_key"` // AES Key yang dibungkus RSA (Hex)
	Payload      string `json:"payload"`       // Secrets yang dienkripsi AES-GCM (Hex)
	Nonce        string `json:"nonce"`         // Nonce AES-GCM (Hex)
}

type VaultSecrets struct {
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

// getVaultPath mempermudah handling absolute path di home directory
func getVaultPath(fileName string) string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, VaultDir, fileName)
}

// initGasakKeys — Memastikan keypair RSA lokal tersedia tanpa merusak authorized_keys OS
func initGasakKeys() error {
	dir := getVaultPath("")
	_ = os.MkdirAll(dir, 0700)

	privPath := getVaultPath(PrivateKeyFile)
	pubPath := getVaultPath(PublicKeyFile)

	// Jika keypair sudah ada, skip generation
	if _, err := os.Stat(privPath); err == nil {
		return nil
	}

	// Generate RSA 2048-bit Keypair
	privateKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return fmt.Errorf("failed to generate RSA key: %w", err)
	}

	// Save Private Key (PEM format) dengan CHMOD 600
	privFile, err := os.OpenFile(privPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
	if err != nil {
		return err
	}
	defer privFile.Close()

	err = pem.Encode(privFile, &pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: x509.MarshalPKCS1PrivateKey(privateKey),
	})
	if err != nil {
		return err
	}

	// Save Public Key (PEM format) dengan CHMOD 644
	pubFile, err := os.OpenFile(pubPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0644)
	if err != nil {
		return err
	}
	defer pubFile.Close()

	pubASN1, err := x509.MarshalPKIXPublicKey(&privateKey.PublicKey)
	if err != nil {
		return err
	}

	return pem.Encode(pubFile, &pem.Block{
		Type:  "PUBLIC KEY",
		Bytes: pubASN1,
	})
}

func loadVault() (*VaultSecrets, error) {
	vaultPath := getVaultPath(VaultFile)
	privPath := getVaultPath(PrivateKeyFile)

	// Pastikan keypair siap pas runtime
	if err := initGasakKeys(); err != nil {
		return nil, err
	}

	if _, err := os.Stat(vaultPath); os.IsNotExist(err) {
		return nil, fmt.Errorf("file vault lokal belum dibikin men (jalanin install.sh dulu biar sinkron)")
	}

	// 1. Baca Private Key Lokal
	privBytes, err := os.ReadFile(privPath)
	if err != nil {
		return nil, err
	}
	block, _ := pem.Decode(privBytes)
	if block == nil {
		return nil, fmt.Errorf("invalid private key format")
	}
	privateKey, err := x509.ParsePKCS1PrivateKey(block.Bytes)
	if err != nil {
		return nil, err
	}

	// 2. Baca Data Vault Terenkripsi
	vaultBytes, err := os.ReadFile(vaultPath)
	if err != nil {
		return nil, err
	}

	var envelope VaultData
	if err := json.Unmarshal(vaultBytes, &envelope); err != nil {
		return nil, err
	}

	encryptedKey, _ := hex.DecodeString(envelope.EncryptedKey)
	ciphertext, _ := hex.DecodeString(envelope.Payload)
	nonce, _ := hex.DecodeString(envelope.Nonce)

	aesKey, err := rsa.DecryptOAEP(sha256.New(), rand.Reader, privateKey, encryptedKey, nil)
	if err != nil {
		return nil, fmt.Errorf("decryption gagal. Keypair di lokal ga match sama yang didaftarin ke server pusat men: %w", err)
	}

	aesBlock, err := aes.NewCipher(aesKey)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(aesBlock)
	if err != nil {
		return nil, err
	}

	plaintext, err := gcm.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return nil, fmt.Errorf("decryption payload gagal: %w", err)
	}

	var secrets VaultSecrets
	if err := json.Unmarshal(plaintext, &secrets); err != nil {
		return nil, err
	}

	return &secrets, nil
}

func applyVaultSecrets(s *VaultSecrets) {
	os.Setenv("GLPI_URL", s.GLPIUrl)
	os.Setenv("OUTLINE_URL", s.OutlineURL)
	os.Setenv("OUTLINE_API_KEY", s.OutlineAPIKey)
	os.Setenv("LINEAR_API_KEY", s.LinearAPIKey)
	os.Setenv("PARKEE_SSH_USER", s.SshUser)
	os.Setenv("PARKEE_SSH_PASS", s.SshPass)
	os.Setenv("CMS_DB_HOST", s.CmsDbHost)
	os.Setenv("CMS_DB_PORT", s.CmsDbPort)
	os.Setenv("CMS_DB_USER", s.CmsDbUser)
	os.Setenv("CMS_DB_PASS", s.CmsDbPass)
	os.Setenv("CMS_DB_NAME", s.CmsDbName)

	GLPIUrl = s.GLPIUrl
	OutlineURL = s.OutlineURL
	OutlineAPIKey = s.OutlineAPIKey
	LinearAPIKey = s.LinearAPIKey
	SshPass = s.SshPass
	CmsDbHost = s.CmsDbHost
	CmsDbPort = s.CmsDbPort
	CmsDbUser = s.CmsDbUser
	CmsDbPass = s.CmsDbPass
	CmsDbName = s.CmsDbName
}
