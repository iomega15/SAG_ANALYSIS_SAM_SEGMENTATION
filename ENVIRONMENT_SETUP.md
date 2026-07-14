# Environment Setup — SAM-Based Printability/Sag Analysis Pipeline

Setup instructions for running `IMAGE_ANALYSIS4.m` (and the companion
`VALVE_CLOSURE_ANALYSIS` pipeline, which shares this Python/SAM stack via
`addpath`) on a new Windows machine. All steps are doable as a **regular
(non-admin) user** except where noted.

## 1. Requirements overview

| Component | Requirement |
|---|---|
| MATLAB toolboxes | Image Processing Toolbox; Computer Vision Toolbox (for `ocr()`) |
| Python | 3.9–3.11 (3.10 used in this setup) |
| Python packages | `opencv-python`, `numpy`, `torch` (CPU build), `torchvision` (matching build), `segment-anything` |
| External binary | Microsoft Visual C++ Redistributable x64 (required by torch; **needs admin**) |
| Model file | `sam_vit_b_01ec64.pth` (~358 MB, Meta's "vit_b" SAM checkpoint) |

MATLAB toolboxes are installed via the normal Add-Ons dialog — no special
steps. Statistics/Curve Fitting/Deep Learning/Parallel Computing/Signal
Processing toolboxes are **not** used anywhere in either pipeline.

## 2. Python virtual environment

Check what `python` actually resolves to before assuming it's missing —
Windows ships a stub "App Execution Alias" that silently no-ops instead of
erroring:

```powershell
python --version         # if this prints nothing, it's the WindowsApps stub
py --version              # the separate Python Launcher often finds a real
                           # install even when `python` is stubbed
```

If `py` works, use it to create the venv (substitutes for `python`
everywhere below). If neither works, install Python from python.org
("Install for me only" — no admin needed) and re-check.

```powershell
cd $env:USERPROFILE
py -m venv SAM_env
.\SAM_env\Scripts\Activate.ps1
```

If activation fails with *"running scripts is disabled on this system"*,
fix it as your own user (no admin):

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

Prompt should now show `(SAM_env)`. Confirm `python --version` reports the
real version (not blank).

## 3. Install Python packages

```powershell
pip install opencv-python numpy
pip install torch --index-url https://download.pytorch.org/whl/cpu
pip install torchvision==0.20.1 --index-url https://download.pytorch.org/whl/cpu
pip install https://github.com/facebookresearch/segment-anything/archive/refs/heads/main.zip
```

Notes:
- CPU-only wheel unless the machine has a usable CUDA GPU.
- `torchvision==0.20.1` pairs with `torch 2.5.1`; if pip resolves a
  different torch version, adjust the torchvision pin to match, or drop the
  pin and re-verify versions afterward — an unpinned install can silently
  bump/downgrade torch.
- The GitHub **zip** URL (not `git+https://...`) avoids needing `git`
  installed on the machine at all.

If torch fails to import with a DLL load error mentioning
`c10.dll`/"Microsoft Visual C++ Redistributable is not installed" — that's
the **one step in this whole setup that needs admin**:

1. Download & run: `https://aka.ms/vs/16/release/vc_redist.x64.exe`
2. Accept the UAC prompt.
3. Close and reopen PowerShell, reactivate the venv, retry.

## 4. Verify the Python side

```powershell
python -c "import cv2, numpy, torch, torchvision; from segment_anything import sam_model_registry; print('OK')"
```

If this errors with a *different* missing module than the above, that's a
transitive dependency of `segment_anything` (its `predictor.py` imports
`torchvision.transforms` even though the pipeline's own script never calls
it directly) — just `pip install` whatever it names and retry.

## 5. SAM model checkpoint

`sam_vit_b_01ec64.pth` must live directly in `SAG_ANALYSIS_SAM_SEGMENTATION\`
(that's the first path `segmentLumenSAM2.m`'s `candidatePaths` checks).

- If the new machine shares the same Dropbox account as the existing
  pipeline, it's already there (or will sync there) — no action needed.
- Otherwise, download the "vit_b" checkpoint from Meta's public SAM release
  and place it in that folder.

## 6. Connect MATLAB to this Python environment

This step happens **inside MATLAB's Command Window, not PowerShell** —
`pyenv(...)` is a MATLAB function, and PowerShell can't parse its
`Name="Value"` syntax.

```matlab
pyenv(Version="C:\Users\<user>\SAM_env\Scripts\python.exe", ExecutionMode="OutOfProcess")
```

Use `ExecutionMode="OutOfProcess"`, not the default. In-process execution
shares MATLAB's memory space with Python/torch; a crash on the Python side
can silently take the whole MATLAB session down with no catchable error —
observed as a run that stalls partway through with no error message.
Out-of-process isolates that failure into a normal, catchable `pyrunfile`
error instead.

`pyenv()` can only be changed while `Status: NotLoaded` — if MATLAB already
loaded some Python interpreter earlier in the session, this call errors
instead of applying. Restart MATLAB if that happens.

**This is not persisted** — `pyenv()` has to be re-run every MATLAB
session, since no `pyenv()` call exists anywhere in the tracked code.
Either add it to `startup.m` (machine-local only) or add a guarded
`pyenv()` check to the top of the pipeline scripts themselves (repo-wide,
applies to every machine automatically).

## 7. Final verification

```matlab
pyenv                                          % Executable = venv path;
                                                % ExecutionMode = OutOfProcess
py.importlib.import_module('segment_anything');
py.importlib.import_module('torch');
```

Silence on the last two lines (no red traceback) confirms Python actually
loaded through the MATLAB bridge — this is the real test; `pyenv` alone
only shows configuration, not that it works.

## 8. Path portability (already handled by the code)

Both pipelines resolve their Dropbox root automatically:

```matlab
dropboxRoot = fullfile(getenv('USERPROFILE'), 'Dropbox');
```

So no path edits are needed in the scripts themselves on a new machine —
only the environment above.
