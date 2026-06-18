package main

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/charmbracelet/glamour"
	"github.com/charmbracelet/huh"
	"github.com/charmbracelet/lipgloss"
	"github.com/joho/godotenv"
)

const (
	SpreadsheetID = "1A0ce374Dgw3pS4w05Yw9y1flJK5pZi6D-UUII6PG5VM"
	SheetGID      = "463772829"

	AppVersion = "1.1.17"
)

var (
	CacheTTL = time.Hour

	GLPIUrl       string
	OutlineURL    string
	OutlineAPIKey string
	LinearAPIKey  string
	SshPass       string

	CmsDbHost string
	CmsDbPort string
	CmsDbUser string
	CmsDbPass string
	CmsDbName string
)

func init() {
	// ── Priority 1: GASAK Vault (encrypted local vault) ──────────
	// Ini path utama — secret dienkripsi pake Hybrid RSA-AES, gak ada plaintext di disk
	vaultLoaded := false
	if secrets, err := loadVault(); err == nil {
		applyVaultSecrets(secrets)
		vaultLoaded = true
	} else {
		// Analisis AI Internal Parkee: Supaya ga noise di local dev machine / fresh install,
		// kita cek dulu apakah file vault-nya memang eksis di dalam path target.
		vaultDir := filepath.Join(os.Getenv("HOME"), ".config/gasak")
		vaultPath := filepath.Join(vaultDir, "vault")

		if _, statErr := os.Stat(vaultPath); statErr == nil {
			// File vault-nya ada, tapi kenapa gagal load? Berarti keypair RSA ga match / corrupt!
			fmt.Fprintf(os.Stderr, "[VAULT] Gagal load vault: %v — fallback ke .env\n", err)
		}
		// Kalau file vault-nya emang gaada (Expected State saat develop / fresh install), silent aja men.
	}

	// ── Priority 2: .env fallback ─────────────────────────────────
	// Fallback buat backward compatibility — engineer yang belum
	// curl ulang installer setelah vault rollout tetap bisa jalan
	if !vaultLoaded {
		home, _ := os.UserHomeDir()
		locations := []string{
			".env",
			filepath.Join(home, "gasak-dist", ".env"),
			filepath.Join(home, ".env"),
		}
		for _, loc := range locations {
			if err := godotenv.Load(loc); err == nil {
				break
			}
		}
	}

	// ── Load ke global vars ───────────────────────────────────────
	GLPIUrl = os.Getenv("GLPI_URL")
	OutlineURL = os.Getenv("OUTLINE_URL")
	OutlineAPIKey = os.Getenv("OUTLINE_API_KEY")
	LinearAPIKey = os.Getenv("LINEAR_API_KEY")

	// Fallback password ssh support default PARKEE
	SshPass = os.Getenv("PARKEE_SSH_PASS")
	if SshPass == "" {
		SshPass = "REMOVED_PASSWORD"
	}

	// Credential Database CMS Pusat untuk parsing di internal GASAK / script python
	CmsDbHost = os.Getenv("CMS_DB_HOST")
	CmsDbPort = os.Getenv("CMS_DB_PORT")
	CmsDbUser = os.Getenv("CMS_DB_USER")
	CmsDbPass = os.Getenv("CMS_DB_PASS")
	CmsDbName = os.Getenv("CMS_DB_NAME")
	if CmsDbPort == "" {
		CmsDbPort = "5432"
	}
}

const UpdateURL = "http://10.70.0.110:9001/version.txt"
const BinaryURL = "http://10.70.0.110:9001/gasak"

var (
	csvURL       = fmt.Sprintf("https://docs.google.com/spreadsheets/d/%s/export?format=csv&gid=%s", SpreadsheetID, SheetGID)
	cacheFile    = filepath.Join(os.Getenv("HOME"), ".cache", "parkee", "master_loc.csv")
	deployScript = filepath.Join(os.Getenv("HOME"), "gasak-dist", "deploy_parkee.py")
)

var (
	accentStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("#ff00ff"))

	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("#00ff87"))

	borderStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("#00ffff")).
			Padding(0, 2)

	greetStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("#ffd700"))

	dimStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#5f5f5f"))

	okStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("#00ff87"))
	errStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("#ff005f"))
	infoStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#00ffff"))
	warnStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#ffd700"))
)

func logOK(msg string)   { fmt.Println(okStyle.Render("  ✔  " + msg)) }
func logErr(msg string)  { fmt.Println(errStyle.Render("  ✘  " + msg)) }
func logInfo(msg string) { fmt.Println(infoStyle.Render("  ℹ  " + msg)) }
func logWarn(msg string) { fmt.Println(warnStyle.Render("  ⚠  " + msg)) }

func getGreeting() string {
	h := time.Now().Hour()
	switch {
	case h < 11:
		return "Pagi men, ngopi dulu jangan lupa yak"
	case h < 15:
		return "Siang men, jangan lupa check task yak"
	case h < 18:
		return "Sore men, rokok kopi dulu ga sih?..."
	default:
		return "Sudah malam? atau sudah tau?"
	}
}

func getUserName() string {
	u, err := user.Current()
	if err != nil {
		return "men"
	}
	name := u.Username
	for _, sep := range []string{".", "_", "-"} {
		if idx := strings.Index(name, sep); idx > 0 {
			name = name[:idx]
			break
		}
	}
	if len(name) > 0 {
		return strings.ToUpper(name[:1]) + name[1:]
	}
	return "Men"
}

func showSplash() {
	clearScreen()

	name := getUserName()
	greeting := getGreeting()
	now := time.Now().Format("Mon, 02 Jan 2006  15:04")

	rawASCII := `  ██████╗  █████╗ ███████╗ █████╗ ██╗  ██╗
  ██╔════╝ ██╔══██╗██╔════╝██╔══██╗██║ ██╔╝
  ██║  ███╗███████║███████╗███████║█████╔╝
  ██║   ██║██╔══██║╚════██║██╔══██║██╔═██╗
  ╚██████╔╝██║  ██║███████║██║  ██║██║  ██╗
   ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝`

	ascii := accentStyle.Render(rawASCII)
	subtitle := dimStyle.Render("  Parkee Gasak CLI  •  Fadlan's Handmade  •  v" + AppVersion)

	greetLine := greetStyle.Render("Konichiwa " + name + ",")
	greetLine2 := greetStyle.Render(greeting)
	timeLine := dimStyle.Render(now)

	splashContent := fmt.Sprintf(
		"%s\n%s\n\n%s\n%s\n%s",
		ascii, subtitle, greetLine, greetLine2, timeLine,
	)

	fmt.Println()
	fmt.Println(splashContent)
	fmt.Println()
	fmt.Println(dimStyle.Render("  ───────────────────────────────────────────"))
	fmt.Println()
}

func showMiniHeader() {
	clearScreen()
	name := getUserName()
	now := time.Now().Format("15:04")
	fmt.Println()
	fmt.Println(
		accentStyle.Render("  GASAK") +
			dimStyle.Render("  •  ") +
			greetStyle.Render(name) +
			dimStyle.Render("  •  "+now),
	)
	fmt.Println(dimStyle.Render("  ───────────────────────────────────────────"))
	fmt.Println()
}

type TeleportUser struct {
	Username string
	Role     string
	IsL2     bool
}

type LogSource struct {
	Name         string
	Path         string
	AllowedForL2 bool
	IsDir        bool
	IsAgentLog   bool
}

var logSources = []LogSource{
	// --- SERVER LOGS (ada di server main lokasi) ---
	{Name: "[Server] Watersheep", Path: "/var/log/agent/watersheep", AllowedForL2: false, IsDir: true, IsAgentLog: false},
	{Name: "[Server] Fisherman", Path: "/var/log/agentweebhook", AllowedForL2: false, IsDir: true, IsAgentLog: false},
	{Name: "[Server] Syslog", Path: "/var/log/syslog", AllowedForL2: false, IsDir: false, IsAgentLog: false},
	{Name: "[Server] PostgreSQL", Path: "/var/log/postgresql", AllowedForL2: true, IsDir: true, IsAgentLog: false},

	// --- AGENT LOGS (ada di masing-masing gate PC) ---
	{Name: "[Agent] Parkee Agent (/var/log/agent/parkee-agent)", Path: "/var/log/agent/parkee-agent", AllowedForL2: false, IsDir: true, IsAgentLog: true},
	{Name: "[Agent] Parkee Agent (/var/tmp/application)", Path: "/var/tmp/application", AllowedForL2: false, IsDir: true, IsAgentLog: true},
}

func getTeleportUser() *TeleportUser {
	if role := os.Getenv("TELEPORT_ROLES"); role != "" {
		user := os.Getenv("TELEPORT_USER")
		return &TeleportUser{
			Username: user,
			Role:     role,
			IsL2:     !strings.Contains(role, "support"),
		}
	}

	return parseTeleportStatus()
}

func parseTeleportStatus() *TeleportUser {
	cmd := exec.Command("tsh", "status")
	output, err := cmd.Output()
	if err != nil {
		logWarn("Lu ga login teleport bre, login dulu yah")
		return &TeleportUser{
			Username: "unknown",
			Role:     "support",
			IsL2:     false,
		}
	}

	text := string(output)
	user := &TeleportUser{
		IsL2: false,
	}

	reUser := regexp.MustCompile(`Logged in as:\s+(\S+)`)
	if m := reUser.FindStringSubmatch(text); len(m) > 1 {
		user.Username = m[1]
	}

	reRole := regexp.MustCompile(`Roles:\s+(\S+)`)
	if m := reRole.FindStringSubmatch(text); len(m) > 1 {
		user.Role = m[1]
		user.IsL2 = (m[1] != "support")
	}

	return user
}

type Location struct {
	Unicode string
	Nama    string
	IP      string
}

func loadLocations() ([]Location, error) {
	if err := os.MkdirAll(filepath.Dir(cacheFile), 0755); err != nil {
		return nil, err
	}

	needFetch := true
	if info, err := os.Stat(cacheFile); err == nil {
		if time.Since(info.ModTime()) < CacheTTL {
			needFetch = false
		}
	}

	if needFetch {
		logInfo("Fetching location data dari Google Sheet...")
		resp, err := http.Get(csvURL)
		if err != nil {
			return nil, fmt.Errorf("fetch gagal: %w", err)
		}
		defer resp.Body.Close()

		data, err := io.ReadAll(resp.Body)
		if err != nil {
			return nil, err
		}
		if err := os.WriteFile(cacheFile, data, 0644); err != nil {
			return nil, err
		}
		logOK("Location data diperbarui.")
	}

	f, err := os.Open(cacheFile)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	reader := csv.NewReader(f)
	reader.FieldsPerRecord = -1
	rows, err := reader.ReadAll()
	if err != nil {
		return nil, err
	}
	if len(rows) < 2 {
		return nil, fmt.Errorf("CSV kosong")
	}

	header := rows[0]
	colUni, colNama, colIP := -1, -1, -1
	for i, h := range header {
		switch strings.TrimSpace(strings.ToLower(h)) {
		case "unicode":
			colUni = i
		case "nama lokasi - unicode":
			colNama = i
		case "ip zt":
			colIP = i
		}
	}
	if colUni == -1 || colNama == -1 || colIP == -1 {
		return nil, fmt.Errorf("kolom CSV tidak ditemukan (unicode=%d, nama=%d, ip=%d)", colUni, colNama, colIP)
	}

	var locs []Location
	for _, row := range rows[1:] {
		if len(row) <= max3(colUni, colNama, colIP) {
			continue
		}
		ip := strings.TrimSpace(row[colIP])
		if ip == "" {
			continue
		}
		locs = append(locs, Location{
			Unicode: strings.TrimSpace(row[colUni]),
			Nama:    strings.TrimSpace(row[colNama]),
			IP:      ip,
		})
	}
	return locs, nil
}

func max3(a, b, c int) int {
	m := a
	if b > m {
		m = b
	}
	if c > m {
		m = c
	}
	return m
}

func checkAndRunUpdate() {
	client := http.Client{Timeout: 1 * time.Second}
	resp, err := client.Get(UpdateURL)
	if err != nil {
		return
	}
	defer resp.Body.Close()

	serverVerBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return
	}
	serverVersion := strings.TrimSpace(string(serverVerBytes))

	if serverVersion != "" && serverVersion != AppVersion {
		fmt.Printf("\x1b[33m⚠ Versi baru ada nich (%s). Jalanin auto-update, tungguin men...\x1b[0m\n", serverVersion)

		execPath, err := os.Executable()
		if err != nil {
			return
		}

		respBin, err := http.Get(BinaryURL)
		if err != nil {
			fmt.Println("\x1b[31m✘ Gagal mendownload update.\x1b[0m")
			time.Sleep(1 * time.Second)
			return
		}
		defer respBin.Body.Close()

		os.Remove(execPath)

		out, err := os.OpenFile(execPath, os.O_CREATE|os.O_WRONLY, 0755)
		if err != nil {
			return
		}
		defer out.Close()

		_, err = io.Copy(out, respBin.Body)
		if err == nil {
			fmt.Println("\x1b[32m✔ GASAK berhasil di-update ke versi terbaru! Jalan lupa source zsh atau bash terus gasak lagi.\x1b[0m")
			os.Exit(0)
		}
	}
}

func main() {
	checkAndRunUpdate()
	showSplash()

	tpUser := getTeleportUser()

	fmt.Println()
	if tpUser.IsL2 {
		logOK(fmt.Sprintf("Detected as %s (Role: %s)", tpUser.Username, tpUser.Role))
	} else {
		logInfo(fmt.Sprintf("Detected as %s (Role: %s)", tpUser.Username, tpUser.Role))
	}
	fmt.Println()
	fmt.Println(dimStyle.Render("  Lu mau gasak apaan hari ini men?"))
	fmt.Println()

	for {
		var action string
		var options []huh.Option[string]

		options = append(options, huh.NewOption("Login Teleport", "tsh_login"))

		if tpUser.IsL2 {
			options = append(options, huh.NewOption("Central v2", "parkee_cloud"))
		}

		options = append(options,
			huh.NewOption("Tembak Agent", "parkee_launcher"),
			huh.NewOption("Location Lookup", "location_lookup"),
			huh.NewOption("Potong Log", "log_range"),
			huh.NewOption("Ambil Log", "fetch_log"),
			huh.NewOption("Settlement RFS", "settlement_rfs"),
			huh.NewOption("Settlement Decode", "settlement_decode"),
		)

		if tpUser.IsL2 {
			options = append(options,
				huh.NewOption("Superfile", "superfile"),
				huh.NewOption("Search Outline Docs", "search_outline"),
				huh.NewOption("Search Linear Issues", "search_linear"),
				huh.NewOption("Crush (Under Maintenance)", "crush_open"),
				huh.NewOption("GLPI (Under Maintenance)", "open_glpi"),
			)
		}

		options = append(options, huh.NewOption("Exit", "exit"))

		form := huh.NewForm(
			huh.NewGroup(
				huh.NewSelect[string]().
					Title("").
					Options(options...).
					Value(&action),
			),
		).WithTheme(crushTheme())

		if err := form.Run(); err != nil {
			fmt.Println()
			fmt.Println(dimStyle.Render("  Take care men"))
			os.Exit(0)
		}

		fmt.Println()

		if !canAccess(tpUser, action) {
			logErr("Access denied: You don't have permission for this action")
			fmt.Println()
			fmt.Println(dimStyle.Render("  [enter] balik ke menu..."))
			fmt.Scanln()
			showMiniHeader()
			fmt.Println(dimStyle.Render("  Mau gasak apa lagi men?"))
			fmt.Println()
			continue
		}

		switch action {
		case "tsh_login":
			runTSHLogin()
		case "parkee_cloud":
			runParkeeCloud()
		case "parkee_launcher":
			if !checkSSHPass() {
				logErr("sshpass tidak terinstall.")
				logInfo("Jalankan: sudo apt-get install sshpass")
				break
			}
			runParkeeLauncher()
		case "location_lookup":
			if !checkSSHPass() {
				logErr("sshpass tidak terinstall.")
				logInfo("Jalankan: sudo apt-get install sshpass")
				break
			}
			runLocationLookup()
		case "search_outline":
			runOutlineSearch()
		case "search_linear":
			runLinearSearch()
		case "log_range":
			if !checkPythonTk() {
				logErr("python3-tk tidak terinstall.")
				logInfo("Jalankan: sudo apt-get install python3-tk")
				break
			}
			runLogCleaner()
		case "fetch_log":
			if !checkSSHPass() {
				logErr("sshpass tidak terinstall.")
				logInfo("Jalankan: sudo apt-get install sshpass")
				break
			}
			runFetchLog(tpUser)
		case "settlement_rfs":
			runSettlementRFS()
		case "settlement_decode":
			runSettlementDecode()
		case "superfile":
			runSuperfile()
		case "crush_open":
			runCrushOpen()
		case "open_glpi":
			runOpenGLPI()
		case "exit":
			fmt.Println()
			fmt.Println(dimStyle.Render("  Take care men!"))
			os.Exit(0)
		}

		fmt.Println()
		fmt.Println(dimStyle.Render("  [enter] balik ke menu..."))
		fmt.Scanln()
		showMiniHeader()
		fmt.Println(dimStyle.Render("  Mau gasak apa lagi men?"))
		fmt.Println()
	}
}

func canAccess(tpUser *TeleportUser, action string) bool {
	l1Allowed := map[string]bool{
		"tsh_login":         true,
		"parkee_launcher":   true,
		"location_lookup":   true,
		"log_range":         true,
		"fetch_log":         true,
		"settlement_rfs":    true,
		"settlement_decode": true,
		"exit":              true,
	}

	if tpUser.IsL2 {
		return true
	}

	return l1Allowed[action]
}

func crushTheme() *huh.Theme {
	t := huh.ThemeBase()
	t.Focused.SelectedOption = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#ff00ff"))
	t.Focused.UnselectedOption = lipgloss.NewStyle().Foreground(lipgloss.Color("#8a8a8a"))
	t.Focused.SelectSelector = lipgloss.NewStyle().Foreground(lipgloss.Color("#ff00ff")).SetString("▸ ")
	t.Focused.Title = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#00ff87"))
	t.Focused.Description = lipgloss.NewStyle().Foreground(lipgloss.Color("#5f5f5f"))
	t.Focused.TextInput.Cursor = lipgloss.NewStyle().Foreground(lipgloss.Color("#ff00ff"))
	t.Focused.TextInput.Text = lipgloss.NewStyle().Foreground(lipgloss.Color("#ffffff"))
	t.Focused.TextInput.Placeholder = lipgloss.NewStyle().Foreground(lipgloss.Color("#5f5f5f"))
	t.Focused.TextInput.Prompt = lipgloss.NewStyle().Foreground(lipgloss.Color("#ff00ff")).Bold(true)

	return t
}

func runTSHLogin() {
	logInfo("Gasak Teleport Login...")
	fmt.Println(dimStyle.Render("  Using flag --add-keys-to-agent=no (fix OpenSSH compat)"))
	fmt.Println()
	runInteractive("tsh", "login", "--add-keys-to-agent=no")
}

func runParkeeCloud() {
	logInfo("Connecting ke Parkee Agent Central v2 via Teleport...")
	fmt.Println()
	runInteractive("tsh", "ssh", "parkee@parkee-agent-central")
}

func runParkeeLauncher() {
	homeDir, _ := os.UserHomeDir()
	scriptPath := filepath.Join(homeDir, "gasak-dist", "deploy_parkee.py")

	if _, err := os.Stat(scriptPath); os.IsNotExist(err) {
		logErr("Script gaada nih men: " + scriptPath)
		logInfo("Senggol Fadlan biar dia pastiin deploy_parkee.py udah ada di ~/gasak-dist/")
		return
	}

	logInfo("Gasak Tembak Agent")
	fmt.Println()

	cmd := exec.Command("python3", scriptPath)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	if err := cmd.Run(); err != nil {
		logWarn("Tembak script exited: " + err.Error())
	}
}

func runLocationLookup() {
	locs, err := loadLocations()
	if err != nil {
		logErr("Gagal load data lokasi: " + err.Error())
		return
	}

	options := make([]huh.Option[string], 0, len(locs))

	options = append(options, huh.NewOption("Location Lookup", "mass_check"))

	for _, l := range locs {
		label := fmt.Sprintf("%-8s | %-45s | %s", l.Unicode, truncate(l.Nama, 45), l.IP)
		options = append(options, huh.NewOption(label, l.Unicode))
	}

	var selectedUnicode string
	form := huh.NewForm(
		huh.NewGroup(
			huh.NewSelect[string]().
				Title("Pilih lewat dropdown atau ketik aja unicode/nama lokasi nya men):").
				Description(fmt.Sprintf("%d lokasi aktif ditemukan", len(locs))).
				Options(options...).
				Value(&selectedUnicode).
				Filtering(true),
		),
	).WithTheme(crushTheme())

	if err := form.Run(); err != nil {
		logWarn("Pencarian dibatalkan.")
		return
	}

	if selectedUnicode == "mass_check" {
		runMassCheckSafe(locs)
		return
	}

	var selected *Location
	for _, l := range locs {
		if l.Unicode == selectedUnicode {
			loc := l
			selected = &loc
			break
		}
	}
	if selected == nil {
		logErr("Lokasi gaada nich.")
		return
	}

	executeSingleLocationMenu(selected)
}

func executeSingleLocationMenu(selected *Location) {
	for {
		clearScreen()
		showMiniHeader()
		fmt.Println(accentStyle.Render("  Detail Lokasi Terpilih:"))
		info := fmt.Sprintf(
			"  %s : %s\n  %s   : %s\n  %s  : %s",
			accentStyle.Render("Unicode"), selected.Unicode,
			titleStyle.Render("Nama"), selected.Nama,
			infoStyle.Render("IP ZT"), selected.IP,
		)
		fmt.Println(borderStyle.Render(info))
		fmt.Println()

		var subAction string
		subForm := huh.NewForm(
			huh.NewGroup(
				huh.NewSelect[string]().
					Title("Gas check versi men:").
					Options(
						huh.NewOption("SSH ke Lokasi", "ssh_to"),
						huh.NewOption("Check Live Version (Agent, WS, FS)", "check_ver"),
						huh.NewOption("Exit", "back"),
					).
					Value(&subAction),
			),
		).WithTheme(crushTheme())

		if err := subForm.Run(); err != nil || subAction == "back" {
			return
		}

		switch subAction {
		case "ssh_to":
			logInfo(fmt.Sprintf("SSH as support@%s ...", selected.IP))
			fmt.Println()

			// Langsung pakai SshPass global yang sudah di-load saat aplikasi start
			runInteractive("sshpass", "-p", SshPass, "ssh",
				"-o", "StrictHostKeyChecking=no",
				"-o", "ConnectTimeout=5",
				fmt.Sprintf("support@%s", selected.IP))
			fmt.Println("\n[enter] balik ke menu detail...")
			fmt.Scanln()

		case "check_ver":
			fmt.Println(accentStyle.Render("\n=== CHECKING LIVE VERSION (DIRECT) ==="))
			fetchLiveVersionsInlineSafe(selected.IP)
			fmt.Println("\n[enter] balik ke menu detail...")
			fmt.Scanln()
		}
	}
}

func runMassCheckSafe(locs []Location) {
	var unicodesInput string
	form := huh.NewForm(
		huh.NewGroup(
			huh.NewInput().
				Title("Masukkan List Unicode (pisahkan pake spasi, contoh: 016 012 014):").
				Placeholder("016 012 014 015").
				Value(&unicodesInput),
		),
	).WithTheme(crushTheme())

	if err := form.Run(); err != nil || strings.TrimSpace(unicodesInput) == "" {
		return
	}

	targets := strings.Fields(strings.ToLower(unicodesInput))
	if len(targets) == 0 {
		logWarn("Kaga ada unicode yang lu input men.")
		return
	}

	clearScreen()
	fmt.Println(accentStyle.Render("=== PARKEE MASS VERSION CHECKER (DIRECT FETCH) ==="))
	fmt.Println(dimStyle.Render("Concurrent Agent, WS, & FS Extraction Engine"))
	fmt.Println()

	for _, target := range targets {
		var foundLoc *Location
		for _, l := range locs {
			if strings.ToLower(l.Unicode) == target {
				loc := l
				foundLoc = &loc
				break
			}
		}

		fmt.Println(accentStyle.Render(fmt.Sprintf("=== %s ===", strings.ToUpper(target))))
		if foundLoc == nil {
			logErr(fmt.Sprintf("Unicode %s kagak ada di data Google Sheet", target))
			fmt.Println()
			continue
		}

		fmt.Printf("Location: %s\n", foundLoc.Nama)
		fmt.Printf("IP-Zerotier=%s\n", foundLoc.IP)

		fetchLiveVersionsInlineSafe(foundLoc.IP)
		fmt.Println()
	}
}

func fetchLiveVersionsInlineSafe(ip string) {
	type inlineRes struct {
		label string
		ver   string
	}
	ch := make(chan inlineRes, 3)

	checkAPI := func(label, url string) {
		client := http.Client{Timeout: 3 * time.Second}
		resp, err := client.Get(url)
		if err != nil {
			ch <- inlineRes{label, "-"}
			return
		}
		defer resp.Body.Close()
		var d map[string]interface{}
		if err := json.NewDecoder(resp.Body).Decode(&d); err != nil {
			ch <- inlineRes{label, "-"}
			return
		}
		b, _ := d["build"].(map[string]interface{})
		v, _ := b["version"].(string)
		if v == "" {
			v = "-"
		}
		ch <- inlineRes{label, v}
	}

	go checkAPI("WS", fmt.Sprintf("http://%s:9005/actuator/info", ip))
	go checkAPI("FS", fmt.Sprintf("http://%s:8888/actuator/info", ip))

	go func() {
		cmd := exec.Command("sshpass", "-p", SshPass,
			"ssh", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=3",
			"support@"+ip,
			"unzip -p /mnt/shared/production/parkee-agent-production.jar META-INF/MANIFEST.MF 2>/dev/null | grep 'Implementation-Version' | cut -d: -f2 | tr -d ' \\r '",
		)
		out, err := cmd.Output()
		v := strings.TrimSpace(string(out))
		if err != nil || v == "" {
			v = "-"
		}
		ch <- inlineRes{"Agent", v}
	}()

	res := map[string]string{"Agent": "-", "WS": "-", "FS": "-"}
	for i := 0; i < 3; i++ {
		r := <-ch
		res[r.label] = r.ver
	}

	cleanAgent := strings.TrimPrefix(strings.TrimSpace(res["Agent"]), "v")
	cleanWS := strings.TrimPrefix(strings.TrimSpace(res["WS"]), "v")
	cleanFS := strings.TrimPrefix(strings.TrimSpace(res["FS"]), "v")

	if cleanAgent != "-" {
		fmt.Printf("Agent=v%s\n", cleanAgent)
	} else {
		fmt.Println("Agent=-")
	}
	if cleanWS != "-" {
		fmt.Printf("WS=v%s\n", cleanWS)
	} else {
		fmt.Println("WS=-")
	}
	if cleanFS != "-" {
		fmt.Printf("FS=v%s\n", cleanFS)
	} else {
		fmt.Println("FS=-")
	}
}

type OutlineDocument struct {
	ID    string `json:"id"`
	Title string `json:"title"`
	Text  string `json:"text"`
	URL   string `json:"url"`

	Collection struct {
		Name string `json:"name"`
	} `json:"collection"`
}

type OutlineSearchResponse struct {
	Data []struct {
		Document OutlineDocument `json:"document"`
	} `json:"data"`

	Status int  `json:"status"`
	OK     bool `json:"ok"`
}

func outlineSearch(keyword string) {
	logInfo("Searching Outline docs...")

	payload := fmt.Sprintf(`{"query": "%s", "limit": 10, "includeArchived": false}`, keyword)

	req, err := http.NewRequest(
		"POST",
		"https://docs.sistemparkiran.com/api/documents.search",
		strings.NewReader(payload),
	)
	if err != nil {
		logErr(err.Error())
		return
	}

	req.Header.Set("Authorization", "Bearer "+OutlineAPIKey)
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 20 * time.Second}

	resp, err := client.Do(req)
	if err != nil {
		logErr("Outline request gagal: " + err.Error())
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		logErr(fmt.Sprintf("Outline error (%d): %s", resp.StatusCode, string(body)))
		return
	}

	bodyBytes, _ := io.ReadAll(resp.Body)

	var result OutlineSearchResponse
	if err := json.Unmarshal(bodyBytes, &result); err != nil {
		logErr("Decode gagal: " + err.Error())
		return
	}

	if !result.OK || len(result.Data) == 0 {
		logWarn(fmt.Sprintf("Gak ada dokumen untuk keyword itu men \"%s\".", keyword))
		return
	}

	fmt.Println()
	fmt.Println(accentStyle.Render(fmt.Sprintf("  %d dokumen ketemu nih: ", len(result.Data))) + titleStyle.Render(keyword))
	fmt.Println()

	renderer, _ := glamour.NewTermRenderer(
		glamour.WithStandardStyle("dark"),
		glamour.WithWordWrap(90),
	)

	for i, item := range result.Data {
		doc := item.Document

		collection := doc.Collection.Name
		if collection == "" {
			collection = "-"
		}

		numBadge := accentStyle.Render(fmt.Sprintf(" %d ", i+1))
		titleLine := titleStyle.Render(doc.Title)
		collLine := dimStyle.Render("Collection : ") + infoStyle.Render(collection)

		var urlLine string
		if doc.URL != "" {
			urlLine = "\n" + dimStyle.Render("URL        : ") + warnStyle.Render("https://docs.sistemparkiran.com"+doc.URL)
		}

		headerBox := lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("#ff00ff")).
			Padding(0, 2).
			Render(fmt.Sprintf("%s %s\n%s%s", numBadge, titleLine, collLine, urlLine))

		fmt.Println(headerBox)

		text := doc.Text
		if len(text) > 600 {
			text = text[:600] + "\n\n*...truncated*"
		}

		var preview string
		if renderer != nil {
			rendered, err := renderer.Render(text)
			if err == nil {
				preview = rendered
			} else {
				preview = dimStyle.Render(text)
			}
		} else {
			preview = dimStyle.Render(text)
		}

		fmt.Print(preview)

		fmt.Println(dimStyle.Render("  ─────────────────────────────────────────────────────"))
		fmt.Println()
	}
}

func runOutlineSearch() {
	for {
		var keyword string

		form := huh.NewForm(
			huh.NewGroup(
				huh.NewInput().
					Title("Cari dokumen di Outline:").
					Placeholder("setup-agent, config, troubleshoot, SOP...").
					Value(&keyword),
			),
		).WithTheme(crushTheme())

		if err := form.Run(); err != nil || strings.TrimSpace(keyword) == "" {
			logWarn("Pencarian dibatalin.")
			return
		}

		outlineSearch(strings.TrimSpace(keyword))

		var next string
		nextForm := huh.NewForm(
			huh.NewGroup(
				huh.NewSelect[string]().
					Title("Mau ngapain lagi?").
					Options(
						huh.NewOption("Search lagi", "search"),
						huh.NewOption("Balik ke menu utama", "back"),
					).
					Value(&next),
			),
		).WithTheme(crushTheme())

		if err := nextForm.Run(); err != nil || next == "back" {
			return
		}
	}
}

func renderMarkdown(content string) {
	r, err := glamour.NewTermRenderer(
		glamour.WithStandardStyle("dark"),
		glamour.WithWordWrap(100),
	)
	if err != nil {
		fmt.Println(content)
		return
	}
	out, err := r.Render(content)
	if err != nil {
		fmt.Println(content)
		return
	}
	fmt.Println(borderStyle.Render(out))
}

type LinearIssue struct {
	ID         string `json:"id"`
	Identifier string `json:"identifier"`
	Title      string `json:"title"`
	Priority   int    `json:"priority"`
	State      struct {
		Name string `json:"name"`
	} `json:"state"`
	Assignee *struct {
		Name string `json:"name"`
	} `json:"assignee"`
	Team struct {
		Name string `json:"name"`
	} `json:"team"`
	URL string `json:"url"`
}

type LinearSearchResponse struct {
	Data struct {
		SearchIssues struct {
			Nodes []LinearIssue `json:"nodes"`
		} `json:"searchIssues"`
	} `json:"data"`
	Errors []struct {
		Message string `json:"message"`
	} `json:"errors,omitempty"`
}

var linearPriorityLabel = map[int]string{
	0: "No Priority",
	1: "Urgent",
	2: "High",
	3: "Medium",
	4: "Low",
}

var linearPriorityColor = map[int]string{
	0: "#5f5f5f",
	1: "#ff005f",
	2: "#ffd700",
	3: "#00ffff",
	4: "#00ff87",
}

func linearSearch(keyword string) {
	logInfo("Searching Linear issues...")

	query := fmt.Sprintf(`{"query": "query { searchIssues(term: \"%s\", first: 10) { nodes { id identifier title priority url state { name } assignee { name } team { name } } } }"}`, keyword)

	req, err := http.NewRequest("POST", "https://api.linear.app/graphql", strings.NewReader(query))
	if err != nil {
		logErr("Request error: " + err.Error())
		return
	}

	req.Header.Set("Authorization", LinearAPIKey)
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 20 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		logErr("Linear request gagal: " + err.Error())
		return
	}
	defer resp.Body.Close()

	bodyBytes, _ := io.ReadAll(resp.Body)

	var result LinearSearchResponse
	if err := json.Unmarshal(bodyBytes, &result); err != nil {
		logErr("Decode gagal: " + err.Error())
		return
	}

	if len(result.Errors) > 0 {
		logErr("Linear API error: " + result.Errors[0].Message)
		return
	}

	issues := result.Data.SearchIssues.Nodes
	if len(issues) == 0 {
		logWarn(fmt.Sprintf("Gak ada issue untuk keyword \"%s\".", keyword))
		return
	}

	fmt.Println()
	fmt.Println(accentStyle.Render(fmt.Sprintf("  %d issue ditemukan untuk: ", len(issues))) + titleStyle.Render(keyword))
	fmt.Println()

	for i, issue := range issues {
		prioLabel := linearPriorityLabel[issue.Priority]
		prioColor := linearPriorityColor[issue.Priority]
		prioBadge := lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color(prioColor)).
			Render("● " + prioLabel)

		assignee := "-"
		if issue.Assignee != nil {
			assignee = issue.Assignee.Name
		}

		numBadge := accentStyle.Render(fmt.Sprintf(" %d ", i+1))
		idBadge := dimStyle.Render(issue.Identifier)
		titleLine := titleStyle.Render(issue.Title)

		headerContent := fmt.Sprintf(
			"%s %s  %s\n%s  %s\n%s  %s\n%s  %s\n%s  %s",
			numBadge, idBadge, titleLine,
			dimStyle.Render("Team     :"), infoStyle.Render(issue.Team.Name),
			dimStyle.Render("Status   :"), warnStyle.Render(issue.State.Name),
			dimStyle.Render("Assignee :"), infoStyle.Render(assignee),
			dimStyle.Render("Priority :"), prioBadge,
		)

		if issue.URL != "" {
			headerContent += fmt.Sprintf("\n%s  %s",
				dimStyle.Render("URL      :"),
				warnStyle.Render(issue.URL),
			)
		}

		headerBox := lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("#ff00ff")).
			Padding(0, 2).
			Render(headerContent)

		fmt.Println(headerBox)
		fmt.Println(dimStyle.Render("  ─────────────────────────────────────────────────────"))
		fmt.Println()
	}
}

func runLinearSearch() {
	for {
		var keyword string

		form := huh.NewForm(
			huh.NewGroup(
				huh.NewInput().
					Title("Cari issue di Linear:").
					Placeholder("bug, deployment, agent, LPR timeout...").
					Value(&keyword),
			),
		).WithTheme(crushTheme())

		if err := form.Run(); err != nil || strings.TrimSpace(keyword) == "" {
			logWarn("Pencarian dibatalin.")
			return
		}

		linearSearch(strings.TrimSpace(keyword))

		var next string
		nextForm := huh.NewForm(
			huh.NewGroup(
				huh.NewSelect[string]().
					Title("Mau ngapain lagi men?").
					Options(
						huh.NewOption("Cari lagi", "search"),
						huh.NewOption("Balik ke menu utama", "back"),
					).
					Value(&next),
			),
		).WithTheme(crushTheme())

		if err := nextForm.Run(); err != nil || next == "back" {
			return
		}
	}
}

func runCrushOpen() {
	cmd := exec.Command("crush")
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		logErr("Gagal buka Crush: " + err.Error())
	}
}

func runOpenGLPI() {
	logInfo("Buka GLPI di browser...")
	cmd := exec.Command("xdg-open", GLPIUrl)
	if err := cmd.Start(); err != nil {
		logErr("xdg-open gagal: " + err.Error())
		logInfo("Buka manual: " + GLPIUrl)
		return
	}
	logOK("GLPI dibuka: " + GLPIUrl)
}

var superfilePaths = []struct {
	Label string
	Path  string
}{
	{"Agent JAR Dir    — /opt/app/agent/parkee-agent/", "/opt/app/agent/parkee-agent/"},
	{"Agent Log Dir    — /home/parkee/logs/", "/home/parkee/logs/"},
	{"Agent Config Dir — /opt/app/agent/", "/opt/app/agent/"},
	{"Home Downloads   — ~/Downloads/", "downloads"},
	{"Home Documents   — ~/Documents/", "documents"},
	{"Custom Path      — Ketik sendiri", "custom"},
}

func runSuperfile() {
	spfPath, err := exec.LookPath("spf")
	if err != nil {
		logErr("Superfile (spf) belum terinstall di mesin ini.")
		fmt.Println()
		logInfo("Install dulu via:")
		fmt.Println(dimStyle.Render("  bash -c \"$(curl -sLo- https://superfile.dev/install.sh)\""))
		fmt.Println()
		logInfo("Pastiin 'spf' ada di PATH setelah install.")
		return
	}

	opts := make([]huh.Option[string], 0, len(superfilePaths))
	for _, p := range superfilePaths {
		opts = append(opts, huh.NewOption(p.Label, p.Path))
	}

	var selectedPath string
	form := huh.NewForm(
		huh.NewGroup(
			huh.NewSelect[string]().
				Title("Mau buka direktori mana di Superfile?").
				Description("Superfile akan terbuka langsung di path yang lu pilih.").
				Options(opts...).
				Value(&selectedPath),
		),
	).WithTheme(crushTheme())

	if err := form.Run(); err != nil {
		logWarn("Dibatalkan.")
		return
	}

	homeDir := os.Getenv("HOME")
	switch selectedPath {
	case "downloads":
		selectedPath = filepath.Join(homeDir, "Downloads")
	case "documents":
		selectedPath = filepath.Join(homeDir, "Documents")
	case "custom":
		var customPath string
		customForm := huh.NewForm(
			huh.NewGroup(
				huh.NewInput().
					Title("Masukkan path direktori:").
					Placeholder("/path/to/directory").
					Value(&customPath),
			),
		).WithTheme(crushTheme())

		if err := customForm.Run(); err != nil || strings.TrimSpace(customPath) == "" {
			logWarn("Dibatalkan.")
			return
		}
		selectedPath = strings.TrimSpace(customPath)
	}

	if info, statErr := os.Stat(selectedPath); statErr != nil || !info.IsDir() {
		logErr(fmt.Sprintf("Path tidak ditemukan atau bukan direktori: %s", selectedPath))
		logInfo("Cek lagi path-nya men, mungkin direktori belum ada di remote ini.")
		return
	}

	fmt.Println()
	logInfo(fmt.Sprintf("Buka Superfile di: %s", selectedPath))
	fmt.Println(dimStyle.Render("  Tekan 'q' di dalam Superfile untuk balik ke GASAK."))
	fmt.Println()

	cmd := exec.Command(spfPath, selectedPath)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 1 {
			logOK("Superfile ditutup. Balik ke GASAK.")
			return
		}
		logErr("Superfile exited dengan error: " + err.Error())
		return
	}
	logOK("Superfile ditutup. Balik ke GASAK.")
}

func runLogCleaner() {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		logErr("Gagal mendapatkan home directory: " + err.Error())
		return
	}

	scriptPath := filepath.Join(homeDir, "gasak-dist", "log_cleaner.py")

	if _, err := os.Stat(scriptPath); os.IsNotExist(err) {
		logErr("File log_cleaner.py gaada nih men: " + scriptPath)
		fmt.Println(dimStyle.Render("Jalanin ulang install.sh rilis terbaru."))
		return
	}

	logInfo("Membuka Log Cleaner UI Version...")
	fmt.Println(dimStyle.Render("  wait bre, lagi dibuka dulu window nya..."))

	cmd := exec.Command("python3", scriptPath)

	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		logErr(fmt.Sprintf("Waduh gagal nih men: %v", err))
		return
	}

	logOK("Kembali ke menu utama GASAK.")
}

func runInteractive(name string, args ...string) {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	if err := cmd.Run(); err != nil {
		logWarn(fmt.Sprintf("Command exit: %s (%v)", name, err))
	}
}

func clearScreen() {
	cmd := exec.Command("clear")
	cmd.Stdout = os.Stdout
	cmd.Run()
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n-3] + "..."
}

func nodeNameFromUnicode(unicode string) string {
	return "server-" + strings.ToLower(strings.TrimSpace(unicode))
}

func commandExists(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

func checkSSHPass() bool {
	return commandExists("sshpass")
}

func checkPythonTk() bool {
	cmd := exec.Command("python3", "-c", "import tkinter")
	return cmd.Run() == nil
}

func runFetchLog(tpUser *TeleportUser) {
	locs, err := loadLocations()
	if err != nil {
		logErr("Gagal load data lokasi: " + err.Error())
		return
	}

	// Step 1: Pilih Lokasi Terlebih Dahulu
	var selectedUnicode string
	var opts []huh.Option[string]
	for _, l := range locs {
		label := fmt.Sprintf("%-8s | %-45s | %s", l.Unicode, truncate(l.Nama, 45), l.IP)
		opts = append(opts, huh.NewOption(label, l.Unicode))
	}

	locForm := huh.NewForm(
		huh.NewGroup(
			huh.NewSelect[string]().
				Title("Pilih lokasi target:").
				Description(fmt.Sprintf("%d lokasi aktif ditemukan", len(locs))).
				Options(opts...).
				Value(&selectedUnicode).
				Filtering(true),
		),
	).WithTheme(crushTheme())

	if err := locForm.Run(); err != nil {
		logWarn("Ambil log dibatalkan.")
		return
	}

	var selected *Location
	for _, l := range locs {
		if l.Unicode == selectedUnicode {
			selected = &l
			break
		}
	}
	if selected == nil {
		logErr("Lokasi tidak valid.")
		return
	}

	fmt.Println()

	// Step 2: Filter log mana saja yang boleh diakses berdasarkan Role (L1 vs L2)
	var sourceOpts []huh.Option[string]
	for _, src := range logSources {
		// Jika log khusus L2 (PostgreSQL) tapi user-nya L1 (support), kita sembunyikan!
		if src.AllowedForL2 && !tpUser.IsL2 {
			continue
		}
		sourceOpts = append(sourceOpts, huh.NewOption(src.Name, src.Name))
	}

	var selectedSourceName string
	sourceForm := huh.NewForm(
		huh.NewGroup(
			huh.NewSelect[string]().
				Title(fmt.Sprintf("Pilih tipe log untuk %s [%s]:", selected.Nama, selected.Unicode)).
				Options(sourceOpts...).
				Value(&selectedSourceName),
		),
	).WithTheme(crushTheme())

	if err := sourceForm.Run(); err != nil {
		logWarn("Ambil log dibatalkan.")
		return
	}

	var chosenSource LogSource
	for _, src := range logSources {
		if src.Name == selectedSourceName {
			chosenSource = src
			break
		}
	}

	fmt.Println()

	// Step 3: Eksekusi penarikan berdasarkan type data
	if chosenSource.IsAgentLog {
		// Log ada di gate PC — perlu flow 2-hop via server main
		fetchAgentGateLog(tpUser, selected, chosenSource.Path, chosenSource.Name)
	} else if chosenSource.IsDir {
		fetchLogFromDir(tpUser, selected, chosenSource.Path, chosenSource.Name)
	} else {
		fetchSingleFile(tpUser, selected, chosenSource.Path, chosenSource.Name)
	}
}

func fetchLogFromDir(tpUser *TeleportUser, loc *Location, remoteDir string, logLabel string) {
	logInfo(fmt.Sprintf("Listing %s di %s [%s]...", logLabel, loc.Nama, loc.IP))
	fmt.Println()

	files, err := listRemoteDir(tpUser, loc, remoteDir)
	if err != nil || len(files) == 0 {
		logErr(fmt.Sprintf("Gagal list dir atau kosong: %s — %v", remoteDir, err))
		return
	}

	maxFiles := 30
	if len(files) > maxFiles {
		files = files[:maxFiles]
	}

	var fileOpts []huh.Option[string]
	for _, f := range files {
		fileOpts = append(fileOpts, huh.NewOption(f, f))
	}

	var selectedFile string
	fileForm := huh.NewForm(
		huh.NewGroup(
			huh.NewSelect[string]().
				Title(fmt.Sprintf("Pilih file log (%s):", logLabel)).
				Description(fmt.Sprintf("%d file ditemukan di %s", len(files), remoteDir)).
				Options(fileOpts...).
				Value(&selectedFile).
				Filtering(true),
		),
	).WithTheme(crushTheme())

	if err := fileForm.Run(); err != nil {
		logWarn("Dibatalin.")
		return
	}

	fmt.Println()

	remotePath := remoteDir + "/" + selectedFile
	scpFile(tpUser, loc, remotePath, selectedFile)
}

func fetchSingleFile(tpUser *TeleportUser, loc *Location, remotePath string, logLabel string) {
	filename := filepath.Base(remotePath)
	logInfo(fmt.Sprintf("Ambil %s dari %s [%s]...", logLabel, loc.Nama, loc.IP))
	fmt.Println()

	scpFile(tpUser, loc, remotePath, filename)
}

func listRemoteDir(tpUser *TeleportUser, loc *Location, remoteDir string) ([]string, error) {
	lsCmd := fmt.Sprintf("cd %s && ls -1t 2>/dev/null | head -50", remoteDir)

	var out []byte
	var err error

	if tpUser.IsL2 {
		nodeName := nodeNameFromUnicode(loc.Unicode)

		remoteUserHost := fmt.Sprintf("%s@%s", nodeName, nodeName)
		remoteCommand := fmt.Sprintf("bash -c '%s'", lsCmd)

		cmd := exec.Command("tsh", "ssh", remoteUserHost, remoteCommand)
		out, err = cmd.Output()
	} else {

		cmd := exec.Command("sshpass", "-p", SshPass,
			"ssh",
			"-o", "StrictHostKeyChecking=no",
			"-o", "ConnectTimeout=5",
			fmt.Sprintf("support@%s", loc.IP),
			fmt.Sprintf("bash -c '%s'", lsCmd),
		)
		out, err = cmd.Output()
	}

	if err != nil {
		return nil, fmt.Errorf("remote execution failed: %w (output: %s)", err, string(out))
	}

	raw := strings.TrimSpace(string(out))
	if raw == "" {
		return nil, fmt.Errorf("direktori %s kosong atau tidak dapat diakses", remoteDir)
	}

	lines := strings.Split(raw, "\n")
	var files []string
	for _, l := range lines {
		l = strings.TrimSpace(l)
		if l != "" {
			files = append(files, l)
		}
	}

	return files, nil
}

func scpFile(tpUser *TeleportUser, loc *Location, remotePath string, filename string) {
	// Bikin local folder: ~/Downloads/logs/<UNICODE>
	destDir := filepath.Join(os.Getenv("HOME"), "Downloads", "logs", strings.ToUpper(loc.Unicode))
	if err := os.MkdirAll(destDir, 0755); err != nil {
		logErr("Gagal membuat folder tujuan lokal: " + err.Error())
		return
	}
	destPath := filepath.Join(destDir, filename)

	logInfo(fmt.Sprintf("Memulai download file remote: %s", remotePath))
	logInfo(fmt.Sprintf("Disimpan ke lokal: %s", destPath))
	fmt.Println(dimStyle.Render("  Sedang menyalin file, mohon tunggu..."))
	fmt.Println()

	var cmd *exec.Cmd

	if tpUser.IsL2 {
		nodeName := nodeNameFromUnicode(loc.Unicode)
		src := fmt.Sprintf("%s@%s:%s", nodeName, nodeName, remotePath)
		cmd = exec.Command("tsh", "scp", src, destPath)
	} else {
		src := fmt.Sprintf("support@%s:%s", loc.IP, remotePath)
		cmd = exec.Command("sshpass", "-p", SshPass,
			"scp",
			"-o", "StrictHostKeyChecking=no",
			"-o", "ConnectTimeout=15",
			src,
			destPath,
		)
	}

	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		logErr(fmt.Sprintf("Proses SCP Gagal: %v", err))
		return
	}

	fmt.Println()
	logOK(fmt.Sprintf("Mantap men! Log berhasil disimpen di: %s", destPath))
}

// ─── Gate PC Log Flow ─────────────────────────────────────────────────────────
// Log agent ada di masing-masing gate PC (pm/pk), bukan di server main.
// Flow: GASAK → SSH server main → query postgres → pilih gate →
//       server main SCP dari gate ke /tmp/ → GASAK SCP dari server main ke laptop

type GateInfo struct {
	UserPC string
	IP     string
}

// queryGatesFromDB SSH ke server main, query postgres, return list gate (yang aktif doang tapi)
func queryGatesFromDB(tpUser *TeleportUser, loc *Location) ([]GateInfo, error) {
	// Ambil data langsung lewat Vault Server Pusat port 9002
	// Tanpa perlu psql direct dari CLI client, Support Engineer aman dari limitasi RBAC DB
	url := fmt.Sprintf("http://10.70.0.110:9002/api/locate-gate?keyword=%s", strings.ToLower(loc.Unicode))

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("gagal membuat request ke vault: %w", err)
	}

	// Inject token pengaman internal
	req.Header.Set("X-Gasak-Token", "gsk_dist_9f2k7x")

	client := &http.Client{Timeout: 7 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("vault server tidak merespon: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		var errResp map[string]string
		_ = json.NewDecoder(resp.Body).Decode(&errResp)
		return nil, fmt.Errorf("error server (%d): %s", resp.StatusCode, errResp["error"])
	}

	type VaultGateData struct {
		NamaLokasi string `json:"nama_lokasi"`
		IPAddress  string `json:"ip_address"`
	}

	var apiData []VaultGateData
	if err := json.NewDecoder(resp.Body).Decode(&apiData); err != nil {
		return nil, fmt.Errorf("gagal membaca payload data gate: %w", err)
	}

	// Mapping ke struct internal GateInfo milik GASAK CLI
	var gates []GateInfo
	for _, data := range apiData {
		gates = append(gates, GateInfo{
			UserPC: data.NamaLokasi,
			IP:     data.IPAddress,
		})
	}

	return gates, nil
}

// listGateLogFiles SSH dari server main ke gate PC, list file di remotePath
func listGateLogFiles(tpUser *TeleportUser, loc *Location, gate GateInfo, remotePath string) ([]string, error) {
	gatePass := fmt.Sprintf("pc%sclient", strings.ToLower(loc.Unicode))

	// Command buat jalan di SERVER Main untuk list file di PC gate
	lsCmd := fmt.Sprintf(
		"sshpass -p '%s' ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 %s@%s 'ls -1t %s 2>/dev/null | head -30'",
		gatePass, gate.UserPC, gate.IP, remotePath,
	)

	var out []byte
	var err error

	if tpUser.IsL2 {
		nodeName := nodeNameFromUnicode(loc.Unicode)
		cmd := exec.Command("tsh", "ssh",
			fmt.Sprintf("%s@%s", nodeName, nodeName),
			lsCmd,
		)
		out, err = cmd.Output()
	} else {
		cmd := exec.Command("sshpass", "-p", SshPass,
			"ssh",
			"-o", "StrictHostKeyChecking=no",
			"-o", "ConnectTimeout=5",
			fmt.Sprintf("support@%s", loc.IP),
			lsCmd,
		)
		out, err = cmd.Output()
	}

	if err != nil {
		return nil, fmt.Errorf("gagal list file di gate: %w", err)
	}

	raw := strings.TrimSpace(string(out))
	if raw == "" {
		return nil, fmt.Errorf("direktori %s kosong di gate %s", remotePath, gate.UserPC)
	}

	var files []string
	for _, l := range strings.Split(raw, "\n") {
		l = strings.TrimSpace(l)
		if l != "" {
			files = append(files, l)
		}
	}
	return files, nil
}

// fetchAgentGateLog main buat orchestrator si pengambil log dari gate PC
func fetchAgentGateLog(tpUser *TeleportUser, loc *Location, remotePath string, logLabel string) {
	// Step 1: Query list gate dari postgres di server main
	logInfo(fmt.Sprintf("List Gate di %s [%s]...", loc.Nama, loc.Unicode))
	fmt.Println()

	gates, err := queryGatesFromDB(tpUser, loc)
	if err != nil {
		logErr("Yah gagal fetch location gate nya men: " + err.Error())
		logWarn("Infoin Fadlan kalo fetching nya error yak!")
		return
	}

	logOK(fmt.Sprintf("%d gate ada nich.", len(gates)))
	fmt.Println()

	// Step 2: Pilih gate dari dropdown
	var gateOpts []huh.Option[string]
	for _, g := range gates {
		label := fmt.Sprintf("%-25s | %s", g.UserPC, g.IP)
		gateOpts = append(gateOpts, huh.NewOption(label, g.UserPC))
	}

	var selectedGateUser string
	gateForm := huh.NewForm(
		huh.NewGroup(
			huh.NewSelect[string]().
				Title(fmt.Sprintf("Pilih Gate untuk %s [%s]:", loc.Nama, loc.Unicode)).
				Description(fmt.Sprintf("%d gate aktif (30 hari terakhir)", len(gates))).
				Options(gateOpts...).
				Value(&selectedGateUser).
				Filtering(true),
		),
	).WithTheme(crushTheme())

	if err := gateForm.Run(); err != nil {
		logWarn("Dibatalin.")
		return
	}

	// Cari GateInfo yang dipilih
	var selectedGate GateInfo
	for _, g := range gates {
		if g.UserPC == selectedGateUser {
			selectedGate = g
			break
		}
	}

	fmt.Println()

	// Step 3: List file log di gate yang dipilih
	logInfo(fmt.Sprintf("Listing %s di gate %s [%s]...", logLabel, selectedGate.UserPC, selectedGate.IP))

	files, err := listGateLogFiles(tpUser, loc, selectedGate, remotePath)
	if err != nil {
		logErr("Gagal list file di gate: " + err.Error())
		logWarn("Cek: gate PC nyala ga?")
		return
	}

	var fileOpts []huh.Option[string]
	for _, f := range files {
		fileOpts = append(fileOpts, huh.NewOption(f, f))
	}

	var selectedFile string
	fileForm := huh.NewForm(
		huh.NewGroup(
			huh.NewSelect[string]().
				Title(fmt.Sprintf("Pilih file log dari %s:", selectedGate.UserPC)).
				Description(fmt.Sprintf("%d file di %s", len(files), remotePath)).
				Options(fileOpts...).
				Value(&selectedFile).
				Filtering(true),
		),
	).WithTheme(crushTheme())

	if err := fileForm.Run(); err != nil {
		logWarn("Dibatalin.")
		return
	}

	fmt.Println()

	// Step 4: 2-hop/jumping SCP — gate → /tmp/ server main → laptop
	scpGateFileViaServerPos(tpUser, loc, selectedGate, remotePath+"/"+selectedFile, selectedFile)
}

// scpGateFileViaServerMain gasak 2-hop/jumping transfer:
// 1. Server main SCP dari gate PC ke /tmp/<filename> di server main
// 2. GASAK SCP dari /tmp/<filename> server main ke laptop
// Cleanup /tmp/<filename> di server main setelah selesai tercopy ke device si requester
func scpGateFileViaServerPos(tpUser *TeleportUser, loc *Location, gate GateInfo, remoteFilePath string, filename string) {
	gatePass := fmt.Sprintf("pc%sclient", strings.ToLower(loc.Unicode))
	tmpPath := fmt.Sprintf("/tmp/%s", filename)

	destDir := filepath.Join(os.Getenv("HOME"), "Downloads", "logs", strings.ToUpper(loc.Unicode), gate.UserPC)
	if err := os.MkdirAll(destDir, 0755); err != nil {
		logErr("Gagal bikin folder lokal nih bre: " + err.Error())
		return
	}
	destPath := filepath.Join(destDir, filename)

	logInfo(fmt.Sprintf("Jumping 1/2 — Narik dari gate %s ke /tmp/ server main...", gate.UserPC))
	fmt.Println(dimStyle.Render("  Ini mungkin butuh waktu ya men, tergantung ukuran file..."))
	fmt.Println()

	// Command buat running di SERVER MAIN: SCP dari gate ke /tmp/
	hop1Cmd := fmt.Sprintf(
		"sshpass -p '%s' scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 %s@%s:%s %s",
		gatePass, gate.UserPC, gate.IP, remoteFilePath, tmpPath,
	)

	var hop1Err error

	if tpUser.IsL2 {
		nodeName := nodeNameFromUnicode(loc.Unicode)
		cmd := exec.Command("tsh", "ssh",
			fmt.Sprintf("%s@%s", nodeName, nodeName),
			hop1Cmd,
		)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		hop1Err = cmd.Run()
	} else {
		cmd := exec.Command("sshpass", "-p", SshPass,
			"ssh",
			"-o", "StrictHostKeyChecking=no",
			"-o", "ConnectTimeout=10",
			fmt.Sprintf("support@%s", loc.IP),
			hop1Cmd,
		)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		hop1Err = cmd.Run()
	}

	if hop1Err != nil {
		logErr(fmt.Sprintf("Jumping 1 gagal — SCP dari gate ke server main: %v", hop1Err))
		logWarn("Kemungkinan: gate PC offline, credential salah, atau sshpass ga ada di server main.")
		return
	}

	logOK(fmt.Sprintf("Oke Jumping 1 selesai — file ada di /tmp/%s di server main.", filename))
	fmt.Println()
	logInfo("Jumping 2/2 — Narik dari server main ke laptop...")
	fmt.Println()

	// Hop/Jumping 2: GASAK SCP dari /tmp/ server main ke laptop
	var hop2Cmd *exec.Cmd

	if tpUser.IsL2 {
		nodeName := nodeNameFromUnicode(loc.Unicode)
		src := fmt.Sprintf("%s@%s:%s", nodeName, nodeName, tmpPath)
		hop2Cmd = exec.Command("tsh", "scp", src, destPath)
	} else {
		src := fmt.Sprintf("support@%s:%s", loc.IP, tmpPath)
		hop2Cmd = exec.Command("sshpass", "-p", SshPass,
			"scp",
			"-o", "StrictHostKeyChecking=no",
			"-o", "ConnectTimeout=15",
			src,
			destPath,
		)
	}

	hop2Cmd.Stdout = os.Stdout
	hop2Cmd.Stderr = os.Stderr

	if err := hop2Cmd.Run(); err != nil {
		logErr(fmt.Sprintf("Jumping ke 2 gagal nih men — SCP dari server main ke laptop: %v", err))
		logWarn(fmt.Sprintf("File masih ada di server main bre: %s — lu bisa SCP manual.", tmpPath))
		return
	}

	// Cleanup /tmp/<filename> di server main
	cleanupCmd := fmt.Sprintf("rm -f %s", tmpPath)
	if tpUser.IsL2 {
		nodeName := nodeNameFromUnicode(loc.Unicode)
		exec.Command("tsh", "ssh", fmt.Sprintf("%s@%s", nodeName, nodeName), cleanupCmd).Run()
	} else {
		exec.Command("sshpass", "-p", SshPass,
			"ssh", "-o", "StrictHostKeyChecking=no",
			fmt.Sprintf("support@%s", loc.IP),
			cleanupCmd,
		).Run()
	}

	fmt.Println()
	logOK(fmt.Sprintf("Mantap men! Log gate berhasil disimpen di: %s", destPath))
	logOK(fmt.Sprintf("File /tmp/%s di server main udah otomatis di-cleanup.", filename))
}

func runSettlementRFS() {
	homeDir, _ := os.UserHomeDir()
	scriptPath := filepath.Join(homeDir, "gasak-dist", "settlement_rfs.py")

	if _, err := os.Stat(scriptPath); os.IsNotExist(err) {
		logErr("Script settlement_rfs.py gaada nih men: " + scriptPath)
		logInfo("Coba jalanin ulang install.sh rilis terbaru.")
		return
	}

	if CmsDbHost == "" || CmsDbUser == "" || CmsDbPass == "" || CmsDbName == "" {
		logErr("CMS DB credentials belum di-set di .env!")
		logInfo("Tambahin key berikut ke file .env lu men:")
		fmt.Println(dimStyle.Render("  CMS_DB_HOST=<host>"))
		fmt.Println(dimStyle.Render("  CMS_DB_PORT=5432"))
		fmt.Println(dimStyle.Render("  CMS_DB_USER=<user>"))
		fmt.Println(dimStyle.Render("  CMS_DB_PASS=<password>"))
		fmt.Println(dimStyle.Render("  CMS_DB_NAME=<dbname>"))
		return
	}

	logInfo("Gasak Settlement RFS...")
	fmt.Println()

	cmd := exec.Command("python3", scriptPath)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	cmd.Env = append(os.Environ(),
		"CMS_DB_HOST="+CmsDbHost,
		"CMS_DB_PORT="+CmsDbPort,
		"CMS_DB_USER="+CmsDbUser,
		"CMS_DB_PASS="+CmsDbPass,
		"CMS_DB_NAME="+CmsDbName,
	)
	if err := cmd.Run(); err != nil {
		logWarn("Script exited: " + err.Error())
	}
}

func runSettlementDecode() {
	homeDir, _ := os.UserHomeDir()
	scriptPath := filepath.Join(homeDir, "gasak-dist", "decode_and_merge.py")

	if _, err := os.Stat(scriptPath); os.IsNotExist(err) {
		logErr("Script decode_and_merge.py gaada nih men: " + scriptPath)
		logInfo("Coba jalanin ulang install.sh rilis terbaru.")
		return
	}

	logInfo("Gasak Settlement Decode...")
	fmt.Println()

	cmd := exec.Command("python3", scriptPath)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	if err := cmd.Run(); err != nil {
		logWarn("Script exited: " + err.Error())
	}
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
}
