---
name: NVIDIA Jetson Development
description: Reference for setting up ML/robotics packages on NVIDIA Jetson devices (Orin Nano, Orin NX, AGX Orin). Covers PyTorch wheel compatibility, unified memory gotchas, model loading patterns, fp16 inference, transformers 5.x patches, MuJoCo headless rendering, and conda environment setup. Use this skill when working with Jetson, aarch64 CUDA, or deploying inference on edge GPU devices.
---

# NVIDIA Jetson Development — Skills Reference

Hard-won engineering notes for setting up ML/robotics packages on NVIDIA Jetson devices (Orin Nano, Orin NX, AGX Orin, etc.). Use this as a reference when installing Python packages, debugging CUDA issues, or deploying inference workloads on Jetson.

---

## 1. Hardware Context — Jetson Orin Series

| Property | Orin Nano 8GB | Orin NX 16GB | AGX Orin 64GB |
|----------|---------------|--------------|---------------|
| GPU architecture | Ampere `sm_87` | Ampere `sm_87` | Ampere `sm_87` |
| Memory model | **Unified** (CPU + GPU share RAM) | Unified | Unified |
| Usable RAM | ~5–6 GB (headless) | ~12–13 GB | ~55–58 GB |

> **Key takeaway:** All Jetson Orin devices use `sm_87` and unified memory. These two facts cause the majority of setup issues.

---

## 2. PyTorch — Use Jetson-Specific Wheels

### The Problem
Standard ARM `aarch64` PyTorch wheels from PyPI (e.g. `torch+cu126`) are **server-ARM builds** targeting `sm_80` / `sm_90` (A100/H100). The Jetson GPU is `sm_87` — not in that arch list. Any CUDA kernel launch fails with:

```
cudaErrorNoKernelImageForDevice
```

### Diagnosis
```python
import torch
print(torch.cuda.get_arch_list())
# ❌ Wrong: ['sm_80', 'sm_90']
# ✅ Correct: should contain 'sm_87'
```

### The Fix
Install the **Jetson-specific wheel** from NVIDIA's Jetson PyPI index:

```bash
# Option 1: NVIDIA Jetson index (recommended)
pip install torch --index-url https://developer.download.nvidia.com/compute/redist/jp/v61

# Option 2: direct wheel install (if you downloaded it)
pip install torch-<version>-cp310-cp310-linux_aarch64.whl --no-deps
```

- Use `--no-deps` to prevent pip from re-resolving constraints and accidentally pulling in a non-Jetson wheel
- Always install PyTorch **first**, before any package that depends on it (torchvision, torchaudio, etc.)

### Verification
```bash
python3 -c "
import torch
print('version:', torch.__version__)
print('arch_list:', torch.cuda.get_arch_list())   # must contain sm_87
t = torch.zeros(4, device='cuda')
print('CUDA kernel: OK')
print('free unified mem:', torch.cuda.mem_get_info(0)[0] / 1e9, 'GB')
"
```

---

## 3. Unified Memory — Gotchas and Monitoring

Jetson's CPU and GPU share physical RAM. This causes behavior that differs from desktop/server GPUs:

| Observation | Explanation |
|-------------|-------------|
| `torch.cuda.memory_allocated()` returns 0 even with model on CUDA | NvMap allocations bypass PyTorch's CUDACachingAllocator — not tracked |
| CPU tensors reduce GPU free memory | They consume the same physical pool |
| `torch.cuda.mem_get_info()` is accurate | Queries NVML directly — use this instead |
| OOM happens earlier than expected | Other processes (desktop, browser, etc.) also consume from the same pool |

### Monitoring memory correctly
```python
free, total = torch.cuda.mem_get_info(0)
print(f"Free: {free/1e9:.2f} GB / Total: {total/1e9:.2f} GB")
```

### Required environment variable
Always set this to avoid NVML internal assert in `CUDACachingAllocator.cpp`:
```bash
export PYTORCH_NO_CUDA_MEMORY_CACHING=1
```

---

## 4. Loading Large Models on Memory-Constrained Jetsons

When total usable memory is ≤8 GB, loading a multi-GB model directly to CUDA often OOMs. Use this **CPU-first loading pattern**:

```python
# 1. Load / construct model on CPU
model = YourModelClass(config)
model.load_state_dict(torch.load("model.safetensors", map_location="cpu"))

# 2. Convert to fp16 WHILE STILL ON CPU — halves peak memory for the .to("cuda") move
model = model.half()

# 3. Now move to CUDA (needs only half the memory vs fp32)
model = model.to("cuda")
model.eval()
```

### Why the order matters
- `.half()` on CPU: weights shrink (e.g. ~1.8 GB → ~0.9 GB) **before** the `.to("cuda")` copy
- `.to("cuda")` then `.half()`: full fp32 weights must fit in unified memory during the move

### Tip: load model before GPU-intensive inits
If your pipeline initializes a renderer or simulator that allocates GPU memory (e.g. MuJoCo EGL uses ~0.5 GB), load the model **first** to ensure enough headroom for `.to("cuda")`.

---

## 5. FP16 Inference

On memory-constrained Jetsons (8 GB), fp32 forward-pass activations for large inputs can exhaust available memory. FP16 is often required.

```python
dtype = torch.float16

# Cast inputs to match model dtype
img = torch.from_numpy(img_uint8).float() / 255.0   # normalize to [0, 1]
img = img.to(device="cuda", dtype=dtype)
state = state_tensor.to(device="cuda", dtype=dtype)
```

> Example: for a VLM model with 512×512 images, fp32 activations need ~3+ GB (OOM on 8 GB), while fp16 activations need ~1.5 GB (fits).

---

## 6. transformers ≥ 5.0 on Jetson

HuggingFace `transformers >= 5.0` added a `caching_allocator_warmup` function that calls `torch.empty(device='cuda')` at **import time**, before any user code runs. On Jetson this triggers an NVML internal assert.

### The Fix
Patch it **before** importing any model class:

```python
import transformers
transformers.modeling_utils.caching_allocator_warmup = lambda *a, **kw: None

# Now safe to import model classes
from transformers import AutoModelForCausalLM, AutoTokenizer
```

---

## 7. MuJoCo on Headless Jetson

```bash
# Select rendering backend via env var
export MUJOCO_GL=egl      # GPU-accelerated headless (preferred on Jetson)
export MUJOCO_GL=osmesa   # Software fallback (no GPU needed, slower)
export MUJOCO_GL=glfw     # Windowed — requires a display

# Required dependency for EGL backend
pip install PyOpenGL
```

### Framebuffer size
Set explicit offscreen dimensions in your scene XML to avoid `Image height > framebuffer height` errors:
```xml
<visual>
  <global offwidth="512" offheight="512"/>
</visual>
```

### Viewer at a named keyframe (not qpos=0)
`python -m mujoco.viewer --mjcf scene.xml` starts at qpos=0 (all joints flat). To start at a named keyframe:
```python
import mujoco
model = mujoco.MjModel.from_xml_path("scene.xml")
data  = mujoco.MjData(model)
mujoco.mj_resetDataKeyframe(model, data, 0)   # 0 = first keyframe in XML
with mujoco.viewer.launch_passive(model, data) as viewer:
    while viewer.is_running():
        mujoco.mj_step(model, data)
        viewer.sync()
```

---

## 8. Conda Environment Setup (Recommended)

```bash
# Create env with correct Python for Jetson cp310 wheels
conda create -n jetson_ml python=3.10 -y
conda activate jetson_ml

# 1. Install Jetson PyTorch wheel FIRST (before other packages pull in wrong torch)
pip install torch --index-url https://developer.download.nvidia.com/compute/redist/jp/v61
# Or from a local wheel:
# pip install torch-<version>-cp310-cp310-linux_aarch64.whl --no-deps

# 2. Install matching torchvision (also from Jetson index or local wheel)
pip install torchvision --index-url https://developer.download.nvidia.com/compute/redist/jp/v61

# 3. Then install your project's remaining deps
pip install -r requirements.txt

# 4. Extra deps commonly needed
pip install PyOpenGL num2words
```

### Key rules
- Always install Jetson PyTorch **first** — other packages may try to pull in the wrong torch as a dependency
- Use `--no-deps` when installing from local `.whl` files to prevent pip from overwriting your Jetson wheel
- Python 3.10 (`cp310`) is the standard target for JetPack 6.x wheels

---

## 9. General Debugging Checklist

When something doesn't work on Jetson, check these in order:

1. **Wrong PyTorch wheel?** — Run `torch.cuda.get_arch_list()` and verify `sm_87` is present
2. **OOM?** — Check `torch.cuda.mem_get_info(0)`, not `torch.cuda.memory_allocated()`
3. **NVML assert on import?** — Patch `caching_allocator_warmup` (see §6) and set `PYTORCH_NO_CUDA_MEMORY_CACHING=1`
4. **CUDA kernel launch failure?** — Almost certainly the wrong PyTorch wheel (see §2)
5. **Rendering errors?** — Set `MUJOCO_GL=egl` and install `PyOpenGL`
6. **Model too large?** — Use CPU-first loading + fp16 conversion (see §4)

---

## 10. Run Command Template

```bash
MUJOCO_GL=egl \
PYTORCH_NO_CUDA_MEMORY_CACHING=1 \
python main.py \
  --your-args here
```

### Environment variables summary

| Variable | Purpose |
|----------|---------|
| `PYTORCH_NO_CUDA_MEMORY_CACHING=1` | Prevents NVML assert in unified memory mode |
| `MUJOCO_GL=egl` | GPU-accelerated headless rendering |
| `HF_HOME=/path/to/fast/storage` | Store HuggingFace model downloads on NVMe if available |
