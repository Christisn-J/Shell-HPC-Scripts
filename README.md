# Shell Workflow Tools

## Overview

This repository contains a collection of modular shell (Zsh/Bash) scripts designed to automate local and remote workflows, especially for HPC and remote Linux systems. The tools simplify tasks such as SSH login, file synchronization, build automation, job submission, and postprocessing.

The scripts are organized into **local** and **remote** components to separate client-side and cluster-side operations.

---

## Features

* SSH login automation
* Remote host setup
* File synchronization (local ↔ remote)
* Build automation
* SLURM job script generation and submission
* Postprocessing and analysis automation
* Workflow automation for simulations and scaling tests
* Modular utility scripts (logging, timers, config handling)

---

## Repository Structure

```
.
├── local/      # Scripts executed on the local machine
├── remote/     # Scripts executed on remote systems / clusters
└── README.md
```

### Local Scripts

Scripts used to manage connections, synchronization, and remote setup:

* `login.zsh` – SSH login helper
* `setup.zsh` – Local setup
* `sync.zsh` – Synchronize files between local and remote
* `zshell/` – Core shell utilities and SSH workflow scripts

### Remote Scripts

Scripts executed on remote clusters for building, running, and analyzing jobs:

* `binac2/` – SLURM build, submit, scaling, and postprocessing scripts
* `kamino/` – Resource and material generation scripts
* `naboo/` – Build configuration

Utilities include:

* Logging tools
* Timers
* Configuration handling
* Environment/module loading
* Batch job submission

---

## Requirements

* Unix/Linux or macOS
* Zsh or Bash
* SSH access to remote systems
* rsync
* SLURM (for cluster job submission)

---

## Getting Started

### Clone the repository

```
git clone https://github.com/YOUR_USERNAME/shell-workflow-tools.git
cd shell-workflow-tools
```

### Configuration

Some scripts require configuration files (e.g., remote hosts, modules, job resources).
Create your personal configuration files from templates:

```
cp config/remoteHosts.template config/remoteHosts.info
cp config/ssh_config.template config/ssh_config
```

Then edit the files and insert your usernames, hostnames, and paths.

## Notes

This repository is intended as a personal workflow toolkit but may serve as a template for similar HPC or remote automation workflows.

---

## License

MIT License
