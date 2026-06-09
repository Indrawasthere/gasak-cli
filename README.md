# 🚀 GASAK CLI

<p align="center">
  <img src="https://github.com/user-attachments/assets/3338e229-675d-4775-9b34-337ace131eac" alt="GASAK CLI">
</p>

<p align="center">
  <strong>Enterprise Operations Automation Toolkit</strong>
</p>

<p align="center">
  Automate deployments, synchronize environments, manage operational workflows, and reduce repetitive engineering tasks through a unified terminal experience.
</p>

---

## 📖 Overview

GASAK CLI is a high-performance terminal-based operations platform built with Go, designed to streamline deployment workflows, infrastructure operations, environment management, and engineering productivity.

Created to eliminate repetitive operational tasks and consolidate multiple engineering tools into a single, fast, and intuitive terminal interface.

Whether you're a DevOps Engineer, SRE, Technical Support Engineer, System Administrator, or Software Engineer, GASAK helps reduce operational overhead and improve execution consistency across environments.

---

## ✨ Core Capabilities

### 🚀 Deployment Automation

* Remote deployment execution
* Service update workflows
* Automated rollout processes
* Environment synchronization

### 🔄 Environment Operations

* Multi-environment management
* Parallel synchronization
* Dependency distribution
* Configuration updates

### 📊 Monitoring & Visibility

* Environment status monitoring
* Operational health checks
* Infrastructure visibility
* Quick operational diagnostics

### 📚 Knowledge Management

* Linear integration
* Outline integration
* Fast documentation lookup
* Centralized information access

### 🧹 Maintenance Utilities

* Automated log cleanup
* Operational housekeeping
* Environment maintenance tools
* Routine task automation

### ⚡ Productivity Enhancements

* Interactive Terminal UI (TUI)
* Keyboard-driven navigation
* Fast command execution
* Unified operational workflow

---

## 🏗 Architecture

GASAK is built with a modular architecture focused on speed, reliability, and maintainability.

### Technology Stack

| Component         | Technology            |
| ----------------- | --------------------- |
| Language          | Go                    |
| Terminal UI       | Bubble Tea            |
| Styling           | Lip Gloss             |
| Remote Operations | SSH                   |
| Automation        | Shell Scripts         |
| Utilities         | Python                |
| Configuration     | Environment Variables |

---

## 📸 Interface Preview

<p align="center">
  <img src="https://github.com/user-attachments/assets/3338e229-675d-4775-9b34-337ace131eac" alt="GASAK CLI Interface">
</p>

---

## ⚙️ Installation

### Clone Repository

```bash
git clone https://github.com/Indrawasthere/gasak-cli.git

cd gasak-cli
```

### Install Dependencies

```bash
go mod tidy
```

### Configure Environment

Create a `.env` file:

```env
LINEAR_API_KEY=
OUTLINE_API_KEY=
GLPI_URL=
OUTLINE_URL=
```

### Run

```bash
go run main.go
```

---

## 🔐 Security

GASAK follows environment-based secret management.

Sensitive credentials are never stored directly in source code and should be supplied through environment variables.

Recommended:

* Use `.env` locally
* Use secret managers in production
* Rotate exposed credentials regularly
* Never commit secrets to Git

---

## 📦 Project Structure

```text
gasak-cli/
├── main.go
├── deploy_dist.sh
├── deploy_parkee_gum.sh
├── log_cleaner.py
├── go.mod
├── go.sum
├── .gitignore
└── README.md
```

---

## 🎯 Target Users

* DevOps Engineers
* Site Reliability Engineers (SRE)
* Technical Support Engineers
* Infrastructure Engineers
* Platform Engineers
* System Administrators

---

## 🛣 Roadmap

* [ ] Plugin System
* [ ] Multi-Server Management
* [ ] Service Health Dashboard
* [ ] Remote Command Center
* [ ] Release Management
* [ ] Environment Profiles
* [ ] Notification Integration
* [ ] Binary Distribution System

---

## 🤝 Contributing

Contributions, ideas, and improvements are welcome.

Open an issue, submit a pull request, or propose new operational workflows.

---

## 📄 License

MIT License

---

<p align="center">
Built with Go, terminal obsession, and an unreasonable dislike of repetitive operational work.
</p>
