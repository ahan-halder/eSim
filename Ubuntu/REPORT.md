# eSim 2.5 Compatibility Investigation on Ubuntu 25.04

## 1. Objective

The goal of this work was to investigate why eSim 2.5 failed to install on
Ubuntu 25.04, identify the root causes of each failure, implement fixes, and
verify that the full installation completes successfully.  This document
records the problems found, the changes made, and how each fix was verified.

---

## 2. Task Requirements

This report corresponds to Task 4 of the FOSSEE eSim Semester Long Internship
(Autumn 2026): *eSim Upgradation (CSE and related fields)*.

Required deliverables:

- Install Ubuntu 25.04 (optionally in VirtualBox).
- Download and attempt to install released eSim 2.5.
- Identify installation and dependency problems on Ubuntu 25.04.
- Inspect `install-eSim.sh` and modify it to fix at least one error.
- Investigate further blockers as needed.
- Produce a well-documented report covering problems, reproduction steps, root
  causes, changes made, fixes, and verification.

---

## 3. Test Environment

| Item | Details |
|---|---|
| Host virtualisation | VirtualBox |
| Guest OS | Ubuntu 25.04 (Plucky Puffin) |
| eSim release | eSim 2.5 (released distribution) |
| Repository | `https://github.com/FOSSEE/eSim`, branch `installers` |
| Fork | `https://github.com/ahan-halder/eSim`, branch `installers` |
| Shell | Bash 5.2 |
| Python | Python 3.13 (system default) |
| Git | git 2.48 |

The test VM was a fresh installation of Ubuntu 25.04 with no prior eSim
components present.

---

## 4. Methodology

1. Started from the released eSim 2.5 distribution (zip archive containing
   `install-eSim.sh` and the `install-eSim-scripts/` directory).
2. Ran `./install-eSim.sh --install` and observed the first failure.
3. Saved the terminal output and identified the failing component.
4. Inspected the relevant Bash installer script to understand the root cause.
5. Applied a targeted fix and re-ran only the affected step where possible.
6. Repeated steps 2–5 for each subsequent blocker encountered.
7. Once all individual fixes were confirmed, ran the full installer end-to-end
   on the test VM.
8. Recorded verification commands and their output.

---

## 5. Summary of Issues

| ID | Component | Issue | Severity | Status |
|---|---|---|---|---|
| 1 | `install-eSim.sh` | Version detection regex did not match Ubuntu 25.04's two-component version string | High | Fixed |
| 2 | `install-eSim.sh` | No routing entry for Ubuntu 25.04 | High | Fixed |
| 3 | `install-eSim-scripts/` | No Ubuntu 25.04-specific eSim installer existed | High | Fixed (new file) |
| 4 | NGHDL bundled installer | Bundled NGHDL tree contained no installer for Ubuntu 25.04 | High | Fixed (new file) |
| 5 | NGHDL dependencies | `libcanberra-gtk-module` not available in Ubuntu 25.04 | Medium | Fixed |
| 6 | GHDL 4.1.0 / LLVM | GHDL 4.1.0 rejected Ubuntu 25.04's default LLVM 20.1.2 | Critical | Fixed |
| 7 | KiCad 8 / library | eSim library copied to wrong KiCad config directory (`6.0` instead of `8.0`) | High | Fixed |
| 8 | KiCad 8 / install flow | `installKicad()` called `exit 0` when KiCad was already present, aborting the installer | High | Fixed |
| 9 | Installer reruns | Stale build directories from failed runs caused permission errors on retry | Medium | Fixed |

---

## 6. Detailed Investigation

### Issue 1 – Version detection regex did not match Ubuntu 25.04

**Component:** `Ubuntu/install-eSim.sh`, function `get_ubuntu_version()`

**Symptoms:**  
The installer printed:

```
Detected Ubuntu Version:
```

(empty string for `FULL_VERSION`) and then fell through to the `*` case:

```
Unsupported Ubuntu version:  (25.04)
```

**Root cause:**  
The upstream `get_ubuntu_version()` extracted the version string with the
pattern `\d+\.\d+\.\d+`, which requires exactly three numeric components.
Ubuntu 25.04's `lsb_release -d` output contains a two-component version
(`25.04`), so the regex matched nothing.

**Original code:**
```bash
FULL_VERSION=$(lsb_release -d | grep -oP '\d+\.\d+\.\d+')
```

**Fix:**  
Changed the pattern to `\d+\.\d+(?:\.\d+)?` so that two-component version
strings also match:

```bash
FULL_VERSION=$(lsb_release -d | grep -oP '\d+\.\d+(?:\.\d+)?')
```

**Why the fix works:**  
The `(?:\.\d+)?` group makes the third component optional.  Ubuntu 25.04
therefore produces `FULL_VERSION=25.04` and the dispatcher continues normally.
The `VERSION_ID` variable (used as the actual `case` key) comes from
`/etc/os-release` and was always correct; only the diagnostic/human-readable
`FULL_VERSION` was broken.

**Verification:**  
After the fix the installer printed:

```
Detected Ubuntu Version: 25.04
```

---

### Issue 2 – No routing entry for Ubuntu 25.04

**Component:** `Ubuntu/install-eSim.sh`, function `run_version_script()`

**Symptoms:**  
Even after fixing the regex, any run of the installer on Ubuntu 25.04 hit the
`*` case and exited with "Unsupported Ubuntu version".

**Root cause:**  
The upstream `run_version_script()` had no `"25.04")` case.  The `case`
statement covered only `22.04`, `23.04`, and `24.04`.

**Fix:**  
Added a `"25.04"` case that routes to the new `install-eSim-25.04.sh`:

```bash
"25.04")
    SCRIPT="$SCRIPT_DIR/install-eSim-25.04.sh"
    ;;
```

**Verification:**  
The installer printed:

```
Running script: .../install-eSim-scripts/install-eSim-25.04.sh --install
```

---

### Issue 3 – No Ubuntu 25.04-specific eSim installer

**Component:** `Ubuntu/install-eSim-scripts/`

**Symptoms:**  
After adding the routing entry, the dispatcher printed:

```
Installation script not found: .../install-eSim-25.04.sh
```

and exited.

**Root cause:**  
The released eSim 2.5 distribution did not include an `install-eSim-25.04.sh`
script.

**Fix:**  
Created `Ubuntu/install-eSim-scripts/install-eSim-25.04.sh`.  This script
handles all installation steps for Ubuntu 25.04, incorporating the fixes for
Issues 4–9 below.

---

### Issue 4 – Bundled NGHDL had no Ubuntu 25.04 installer

**Component:** `nghdl/` (bundled in `nghdl.zip`), `installNghdl()` in
`install-eSim-25.04.sh`

**Symptoms:**  
The original NGHDL installer pattern was:

```bash
unzip -o nghdl.zip
cd nghdl/
./install-nghdl.sh --install
```

`install-nghdl.sh` inside the zip only contained support for Ubuntu 22.04,
23.04, and 24.04.  Running it on Ubuntu 25.04 immediately aborted.

**Root cause:**  
The bundled `nghdl.zip` did not contain a 25.04 installer, and the generic
`install-nghdl.sh` had no mechanism to delegate to a version-specific script.

**Fix:**  
Created `Ubuntu/install-eSim-scripts/install-nghdl-25.04.sh` — a full
Ubuntu 25.04-compatible NGHDL installer — and modified `installNghdl()` in
`install-eSim-25.04.sh` to inject it into the extracted NGHDL tree before
invoking it:

```bash
rm -rf nghdl
unzip -o nghdl.zip
cp "$installer_script_dir/install-nghdl-25.04.sh" \
   "nghdl/install-nghdl-scripts/install-nghdl-25.04.sh"
chmod +x "nghdl/install-nghdl-scripts/install-nghdl-25.04.sh"
(
    cd nghdl || exit 1
    bash install-nghdl-scripts/install-nghdl-25.04.sh --install
)
```

---

### Issue 5 – `libcanberra-gtk-module` unavailable on Ubuntu 25.04

**Component:** `Ubuntu/install-eSim-scripts/install-nghdl-25.04.sh`,
`installDependency()`

**Symptoms:**  
During the NGHDL dependency installation step, `apt-get` reported:

```
E: Package 'libcanberra-gtk-module' has no installation candidate
```

and the installer aborted.

**Root cause:**  
`libcanberra-gtk-module` (the GTK2 variant) was removed from Ubuntu 25.04's
repositories.  Only the GTK3 variant, `libcanberra-gtk3-module`, remains
available.

**Fix:**  
Replaced `libcanberra-gtk-module` with `libcanberra-gtk3-module` in the
dependency list:

```bash
# Before:
sudo apt install -y libcanberra-gtk-module libcanberra-gtk3-module

# After (Ubuntu 25.04):
sudo apt install -y libcanberra-gtk3-module
```

**Why the fix works:**  
`libcanberra-gtk3-module` provides equivalent GTK3 sound-event support and is
present in Ubuntu 25.04's main archive.

---

### Issue 6 – GHDL 4.1.0 incompatible with Ubuntu 25.04's default LLVM 20

**Component:** `Ubuntu/install-eSim-scripts/install-nghdl-25.04.sh`,
`installGHDL()`

This is the most significant compatibility blocker found during the
investigation.

**Symptoms:**  
GHDL's `configure` step aborted with:

```
Unhandled version llvm 20.1.2
```

**Root cause:**  
Ubuntu 25.04 installs LLVM 20.1.2 as its default LLVM version.  GHDL 4.1.0's
configure script has an explicit allowlist of supported LLVM versions; LLVM 20
is not on that list.  GHDL 4.1.0 supports up to LLVM 18.

The original NGHDL configure call used the system-default `llvm-config`:

```bash
./configure --with-llvm-config=/usr/bin/llvm-config
```

On Ubuntu 25.04, `/usr/bin/llvm-config` resolves to LLVM 20, which GHDL 4.1.0
rejects.

**Fix:**  
Install LLVM 18 and Clang 18 alongside the system default (without
replacing it), and explicitly point the GHDL build at them:

```bash
sudo apt install -y llvm-18 llvm-18-dev clang-18

CXX=clang++-18 ./configure --with-llvm-config=/usr/bin/llvm-config-18
```

**Why the fix works:**  
`llvm-18` and `llvm-18-dev` are available in Ubuntu 25.04's repositories as
versioned packages.  Setting `CXX=clang++-18` ensures that GHDL is compiled
with Clang 18, whose ABI matches the LLVM 18 libraries.  Setting
`--with-llvm-config=/usr/bin/llvm-config-18` tells GHDL's configure to query
LLVM 18 rather than the default LLVM 20.  Both must point at the same LLVM
version; mixing compiler and library versions produces link errors.

The system-default `llvm-config` (LLVM 20) is left untouched, so other system
components are unaffected.

**Before / After:**

```
BEFORE:
  Ubuntu 25.04 default: llvm-config → LLVM 20.1.2
  GHDL 4.1.0 configure → "Unhandled version llvm 20.1.2"
  → installation aborts

AFTER:
  llvm-config-18 → LLVM 18.1.8
  CXX=clang++-18 ./configure --with-llvm-config=/usr/bin/llvm-config-18
  → configure succeeds
  → make / sudo make install succeed
  → ghdl --version reports "llvm 18.1.8 code generator"
  → system llvm-config still reports 20.1.2 (unchanged)
```

**Verification:**

```
$ ghdl --version
GHDL 4.1.0 (tarball) [Dunoon edition]
Compiled with GNAT Version: 14.2.0
llvm 18.1.8 code generator

$ llvm-config-18 --version
18.1.8

$ llvm-config --version
20.1.2
```

GHDL uses the LLVM 18 toolchain while Ubuntu retains LLVM 20 as its normal
default.

---

### Issue 7 – eSim symbol library copied to wrong KiCad configuration directory

**Component:** `install-eSim-25.04.sh`, `copyKicadLibrary()`

**Symptoms:**  
KiCad 8 reported no eSim components in the symbol chooser after installation.
The eSim symbol table (`sym-lib-table`) was not visible to KiCad.

**Root cause:**  
Older eSim installer versions copied the symbol table to
`~/.config/kicad/6.0/`.  KiCad 8 stores its per-user configuration under
`~/.config/kicad/8.0/`.  After a fresh KiCad 8 installation the `6.0/`
directory does not exist, so the copy silently succeeded but the file was
placed in a location KiCad 8 never reads.

**Fix:**  
Hard-coded the target to `~/.config/kicad/8.0/` in the Ubuntu 25.04 installer:

```bash
kicad_version="8.0"
kicad_config_dir="$HOME/.config/kicad/$kicad_version"
mkdir -p "$kicad_config_dir"
cp "kicadLibrary/template/sym-lib-table" "$kicad_config_dir/sym-lib-table"
```

**Why the fix works:**  
KiCad 8 reads `~/.config/kicad/8.0/sym-lib-table` at startup.  Writing to
that exact path makes the eSim symbol libraries immediately visible.

---

### Issue 8 – `installKicad()` called `exit 0` when KiCad was already installed

**Component:** `install-eSim-25.04.sh`, `installKicad()`

**Symptoms:**  
When KiCad 8 was already present on the test VM (e.g., after a partial
installation attempt), the installer printed:

```
KiCad 8.0 is already installed.
```

and then terminated immediately, skipping all remaining steps (NGHDL, SKY130
PDK, desktop integration).

**Root cause:**  
The upstream 24.04 installer used `exit 0` in the "already installed" branch:

```bash
echo "KiCad 8.0 is already installed."
exit 0
```

`exit` terminates the entire shell process, not just the function, so the
caller never got control back.

**Fix:**  
Changed `exit 0` to `return 0` so that `installKicad()` returns to its caller
and the installer continues with the subsequent steps:

```bash
echo "KiCad 8.0 is already installed."
return 0
```

---

### Issue 9 – Stale build directories caused permission errors on reinstallation

**Component:** `install-nghdl-25.04.sh` (`installGHDL`, `installVerilator`,
`installNGHDL`), `install-eSim-25.04.sh` (`installNghdl`, `copyKicadLibrary`)

**Symptoms:**  
After a failed partial installation, re-running the installer produced errors
such as:

```
rm: cannot remove 'ghdl-4.1.0/...': Permission denied
tar: ghdl-4.1.0: Cannot open: File exists
```

because a previous `sudo make install` had created root-owned files inside
the build directory.

**Root cause:**  
The original scripts did not clean up build directories before starting a new
build.  If a previous run had invoked `sudo make install` (which writes
root-owned files into the build tree), a subsequent unprivileged `tar -xvf`
or `rm -rf` would fail.

**Fix:**  
Added explicit `rm -rf` of each build directory before extraction in every
relevant function, for example:

```bash
rm -rf "$ghdl"
tar xvf "$ghdl.tar.gz"
```

```bash
rm -rf "$verilator"
tar -xvf "$verilator.tar.xz"
```

```bash
rm -rf "$extracted_dir" "$install_root"
tar -xJf "$source_archive" -C "$HOME"
```

Each of these is run before the corresponding tar extraction so that the
directory is always freshly created with correct ownership.

---

## 7. Files Modified

### `Ubuntu/install-eSim.sh`

The top-level dispatcher script.  Modified to:

- Fix the `FULL_VERSION` regex to accept two-component Ubuntu version strings
  (`\d+\.\d+(?:\.\d+)?`).
- Add the `"25.04"` case that routes to `install-eSim-25.04.sh`.

### `Ubuntu/install-eSim-scripts/install-eSim-25.04.sh` *(new file)*

The Ubuntu 25.04-specific eSim installer.  Contains all the installation
functions adapted for Ubuntu 25.04:

- Injects `install-nghdl-25.04.sh` into the extracted NGHDL tree.
- Captures NGHDL installer exit status cleanly (subshell + manual check).
- Pins KiCad to `kicad=8.0.8+dfsg-1` to avoid the `libgit2` dependency issue.
- Uses `~/.config/kicad/8.0/` as the KiCad configuration directory.
- Uses `return 0` (not `exit 0`) when KiCad is already installed.
- Cleans build/extraction directories before each re-run.

### `Ubuntu/install-eSim-scripts/install-nghdl-25.04.sh` *(new file)*

The Ubuntu 25.04-specific NGHDL installer.  Key changes from the older
`install-nghdl.sh`:

- Installs `llvm-18`, `llvm-18-dev`, and `clang-18` instead of the default
  LLVM version.
- Configures GHDL with
  `CXX=clang++-18 ./configure --with-llvm-config=/usr/bin/llvm-config-18`.
- Replaces `libcanberra-gtk-module` (removed from Ubuntu 25.04) with
  `libcanberra-gtk3-module`.
- Cleans GHDL, Verilator, and NGHDL source directories before extraction to
  make re-runs safe.

---

## 8. Verification

### Syntax checks (no runtime required)

```bash
bash -n Ubuntu/install-eSim.sh
bash -n Ubuntu/install-eSim-scripts/install-eSim-25.04.sh
bash -n Ubuntu/install-eSim-scripts/install-nghdl-25.04.sh
```

All three scripts pass with no errors.

### Component checks on the test VM after full installation

```
$ ghdl --version
GHDL 4.1.0 (tarball) [Dunoon edition]
Compiled with GNAT Version: 14.2.0
llvm 18.1.8 code generator

$ llvm-config-18 --version
18.1.8

$ llvm-config --version
20.1.2

$ ngspice --version
ngspice-42 ...

$ verilator --version
Verilator 4.210 ...

$ command -v nghdl
/usr/local/bin/nghdl

$ command -v esim
/usr/bin/esim
```

The system default LLVM remained at 20.1.2 throughout; GHDL uses the LLVM 18
toolchain exclusively via the versioned binaries.

---

## 9. Final Result

The released eSim 2.5 installer failed on Ubuntu 25.04 due to multiple
independent blockers spanning version detection, missing scripts, an
unavailable package, and a critical LLVM version incompatibility.

Each blocker was isolated, reproduced, and fixed independently.  The most
significant fix was the explicit selection of LLVM 18 and Clang 18 for the
GHDL 4.1.0 build, which resolved the "Unhandled version llvm 20.1.2" failure
without affecting the system-default LLVM installation.

After all fixes were applied, the full eSim 2.5 installation completed
successfully on the Ubuntu 25.04 VirtualBox test VM.  All components —
GHDL, Ngspice (NGHDL build), Verilator, KiCad 8, SKY130 PDK, and the eSim
launcher — were confirmed functional.

---

## 10. Limitations and Future Work

- Testing was performed on a single Ubuntu 25.04 VirtualBox VM.  Behaviour
  on bare-metal Ubuntu 25.04 or other hypervisors has not been validated.
- The work is specifically scoped to Ubuntu 25.04.  Ubuntu 25.10 and future
  releases may introduce further LLVM or packaging changes that require
  additional adaptation.
- The LLVM 18 selection is a workaround for GHDL 4.1.0.  A future upgrade
  to a GHDL version that supports LLVM 20+ would remove the need for the
  versioned LLVM packages.
- The KiCad version pin (`kicad=8.0.8+dfsg-1`) may need updating as newer
  versions stabilise in the Ubuntu 25.04 repository.

---

## 11. References

- FOSSEE eSim repository: <https://github.com/FOSSEE/eSim>
- eSim downloads: <https://esim.fossee.in/downloads>
- GHDL project: <https://github.com/ghdl/ghdl>
- LLVM releases: <https://releases.llvm.org>
- KiCad Ubuntu install guide: <https://www.kicad.org/download/ubuntu/>
