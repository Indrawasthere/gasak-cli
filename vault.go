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
	"os"
	"path/filepath"
)

const (
	VaultDir       = ".config/gasak"
	VaultFile      = "vault"
	PrivateKeyFile = "id_rsa"
	PublicKeyFile  = "id_rsa.pub"
)

type VaultData struct {
	EncryptedKey string `json:"encrypted_key"`
	Payload      string `json:"payload"`
	Nonce        string `json:"nonce"`
}

type VaultSecrets struct {
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
	AgentDbSuffix   string `json:"AGENT_DB_SUFFIX"`
}

func loadVault() (*VaultSecrets, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, fmt.Errorf("gagal nyari home dir: %w", err)
	}

	configPath := filepath.Join(homeDir, VaultDir)
	vaultPath := filepath.Join(configPath, VaultFile)
	privKeyPath := filepath.Join(configPath, PrivateKeyFile)

	// 1. Cek apakah file vault ada
	if _, err := os.Stat(vaultPath); os.IsNotExist(err) {
		return nil, fmt.Errorf("file vault terenkripsi tidak ada di %s", vaultPath)
	}

	// 2. Baca Private Key lokal
	privKeyBytes, err := os.ReadFile(privKeyPath)
	if err != nil {
		return nil, fmt.Errorf("gagal baca private key %s: %w", privKeyPath, err)
	}

	// Sanitize private key block (Takutnya ada noise enter/space)
	block, _ := pem.Decode(privKeyBytes)
	if block == nil {
		return nil, fmt.Errorf("gagal decode PEM private key, format file id_rsa rusak")
	}

	// FIX CRITICAL: Mendukung parsing PKCS#1 (RSA murni) maupun PKCS#8 (Bawaan ssh-keygen modern)
	var privateKey *rsa.PrivateKey
	if block.Type == "RSA PRIVATE KEY" {
		privateKey, err = x509.ParsePKCS1PrivateKey(block.Bytes)
		if err != nil {
			return nil, fmt.Errorf("gagal parse PKCS1 private key: %w", err)
		}
	} else if block.Type == "PRIVATE KEY" {
		key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
		if err != nil {
			return nil, fmt.Errorf("gagal parse PKCS8 private key: %w", err)
		}
		var ok bool
		privateKey, ok = key.(*rsa.PrivateKey)
		if !ok {
			return nil, fmt.Errorf("bukan RSA private key murni di PKCS8 block")
		}
	} else {
		return nil, fmt.Errorf("tipe block private key tidak didukung: %s", block.Type)
	}

	// 3. Baca Data Vault Terenkripsi
	vaultBytes, err := os.ReadFile(vaultPath)
	if err != nil {
		return nil, fmt.Errorf("gagal baca file vault: %w", err)
	}

	var envelope VaultData
	if err := json.Unmarshal(vaultBytes, &envelope); err != nil {
		return nil, fmt.Errorf("format JSON vault rusak/corrupted: %w", err)
	}

	// Decode Hex ke Bytes
	encryptedKey, err := hex.DecodeString(envelope.EncryptedKey)
	if err != nil {
		return nil, fmt.Errorf("failed decode hex encrypted_key")
	}
	ciphertext, err := hex.DecodeString(envelope.Payload)
	if err != nil {
		return nil, fmt.Errorf("failed decode hex payload")
	}
	nonce, err := hex.DecodeString(envelope.Nonce)
	if err != nil {
		return nil, fmt.Errorf("failed decode hex nonce")
	}

	// 4. Decrypt AES Key via RSA Asymmetric
	aesKey, err := rsa.DecryptOAEP(sha256.New(), rand.Reader, privateKey, encryptedKey, nil)
	if err != nil {
		return nil, fmt.Errorf("decryption gagal. Keypair lokal ga match sama server pusat: %w", err)
	}

	// 5. Decrypt Payload via AES-GCM Symmetric
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
		return nil, fmt.Errorf("decryption payload AES gagal: %w", err)
	}

	var secrets VaultSecrets
	if err := json.Unmarshal(plaintext, &secrets); err != nil {
		return nil, fmt.Errorf("gagal unmarshal plaintext secrets ke struct: %w", err)
	}

	return &secrets, nil
}
