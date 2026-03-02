# claude-ros2

> Claude context files and skills for ROS2 & robotics development.

Drop these files into your robotics project to give Claude deep context about your stack — conventions, build system, hardware targets, simulation setup, and ML/VLA deployment patterns.

---

## What's included

```
claude-ros2/
├── CLAUDE.md                        # Project-wide context & coding conventions
├── setup.sh                         # One-command install into any ROS2 workspace
└── .claude/
    └── skills/
        ├── ros2-package/
        │   └── SKILL.md             # Scaffold new ROS2 packages (C++/Python/mixed)
        └── ros2-debug/
            └── SKILL.md             # Debug nodes, topics, TF, time, hardware interfaces
```

### `CLAUDE.md`
Sets the stage for every conversation. Covers:
- Stack overview (ROS2 distros, build system, sim environments, ML runtime, Jetson hardware)
- Repository layout conventions
- Coding style for C++17 and Python 3.10+
- Launch file and parameter YAML rules
- Simulation conventions for MuJoCo, Gazebo, and Isaac Sim
- ML/VLA deployment pipeline and safety requirements
- Behavior guidelines so Claude asks the right questions and avoids common mistakes

### `skills/ros2-package`
A step-by-step instruction set Claude reads before scaffolding any package. Produces:
- Correct `CMakeLists.txt` (ament_cmake / ament_python / mixed)
- `package.xml` with all dependencies
- Node boilerplate (standalone, lifecycle, component — C++ and Python)
- Launch file with `use_sim_time` argument
- Parameter YAML matched to declared parameters
- Test stubs ready for `ament_cmake_gtest` / pytest
- Custom `_msgs` package setup

### `skills/ros2-debug`
Systematic debugging playbook. Covers all 10 most common ROS2 failure patterns:
1. Node exits immediately / process died
2. Topic not receiving data (QoS mismatch, namespace, callback group)
3. TF transform not found / extrapolation errors
4. Parameter not taking effect
5. `colcon build` failures
6. `use_sim_time` issues in simulation
7. `ros2_control` hardware interface not activating
8. High CPU/GPU load on Jetson
9. Launch file silent failure
10. Message type mismatch

Plus simulation-specific debugging (Gazebo, MuJoCo, Isaac Sim), VLA/ML inference diagnostics, and useful one-liners.

---

## Setup

Clone this repo and run `setup.sh` pointing at your ROS2 workspace:

```bash
git clone https://github.com/Rushabh318/claude-ros2.git
cd claude-ros2
./setup.sh /path/to/your/ros2/workspace
```

Or install into the current directory:

```bash
./setup.sh
```

This copies `CLAUDE.md` to your workspace root (where Claude Code auto-reads it) and the skill files to `.claude/skills/`.

### Manual install

```bash
# Copy CLAUDE.md to your project root
cp CLAUDE.md /path/to/your/ros2/workspace/CLAUDE.md

# Copy skills
cp -r .claude/skills /path/to/your/ros2/workspace/.claude/skills
```

### Submodule (keep in sync with upstream)

```bash
cd /path/to/your/ros2/workspace
git submodule add https://github.com/Rushabh318/claude-ros2.git .claude-robotics
.claude-robotics/setup.sh .
```

---

## How Claude uses these files

Claude Code automatically reads `CLAUDE.md` when it's present in the project root. For skills, Claude reads the relevant `SKILL.md` before performing specific tasks — this is triggered by the instructions in `CLAUDE.md`.

You can also explicitly ask Claude to use a skill:
> "Before scaffolding the package, read the skill file at `.claude/skills/ros2-package/SKILL.md`."

---

## Stack coverage

| Area | Covered |
|---|---|
| ROS2 Humble / Iron / Jazzy | ✅ |
| C++17 nodes (standalone, lifecycle, component) | ✅ |
| Python 3.10+ nodes | ✅ |
| ament_cmake / ament_python / mixed | ✅ |
| Custom messages / services / actions | ✅ |
| ros2_control hardware interfaces | ✅ |
| Gazebo (Fortress / Harmonic) | ✅ |
| MuJoCo | ✅ |
| Isaac Sim | ✅ |
| NVIDIA Jetson (Orin / AGX / Nano) | ✅ |
| TensorRT / ONNX inference nodes | ✅ |
| VLA model deployment + safety middleware | ✅ |
| BehaviorTree.CPP v4 | ✅ |

---

## Contributing

PRs welcome. Especially useful additions:
- Skills for URDF/xacro authoring
- Skills for sim-to-real transfer workflows
- Skills for `ros2_control` controller development
- Coverage for additional distros or sim environments

---

## License

Apache 2.0
