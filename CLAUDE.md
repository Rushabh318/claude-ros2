# CLAUDE.md — Robotics & ROS2 Development Context

This file provides Claude with conventions, stack details, and behavioral guidelines
for robotics projects spanning ROS2, embedded hardware, simulation, and ML/VLA deployment.

---

## Stack Overview

| Layer | Technology |
|---|---|
| Middleware | ROS2 (Humble / Iron / Jazzy) |
| Language | C++17/20, Python 3.10+ |
| Build system | colcon + CMake, ament_cmake / ament_python |
| Simulation | Gazebo (Fortress / Harmonic), MuJoCo, Isaac Sim |
| ML runtime | PyTorch, ONNX, TensorRT |
| Edge hardware | NVIDIA Jetson (Orin / AGX), x86 workstation |
| Version control | Git, conventional commits |

---

## Repository Layout

```
<repo-root>/
├── src/                   # ROS2 packages (one directory per package)
│   ├── <pkg_name>/
│   │   ├── include/<pkg_name>/   # C++ headers
│   │   ├── src/                  # C++ sources
│   │   ├── <pkg_name>/           # Python module (same name as package)
│   │   ├── launch/               # Launch files (.py preferred)
│   │   ├── config/               # YAML parameter files
│   │   ├── urdf/                 # URDF / xacro
│   │   ├── test/                 # ament_cmake_gtest / pytest
│   │   ├── CMakeLists.txt
│   │   └── package.xml
├── simulation/            # Standalone sim environments (MuJoCo, Gazebo worlds)
├── ml_models/             # Model weights, ONNX exports, TensorRT engines
├── scripts/               # Dev utilities (not ROS nodes)
├── docker/                # Dockerfiles per target (dev, jetson, sim)
└── docs/
```

---

## Code Conventions

### General
- Prefer **composition over inheritance** for ROS2 nodes (use `rclcpp::Node` or component nodes).
- All parameters must be declared with `declare_parameter()` and loaded from YAML — no hardcoded values.
- Use `rclcpp::Logger` and `RCLCPP_INFO/WARN/ERROR` macros. Never use `std::cout` in node code.
- Time: always use `this->now()` or `rclcpp::Clock`; never `std::chrono::system_clock` directly for ROS time.

### C++
- Standard: C++17 minimum.
- Naming: `snake_case` for variables/functions, `PascalCase` for classes, `UPPER_SNAKE` for constants.
- Use `std::shared_ptr` / `std::unique_ptr`; avoid raw `new/delete`.
- Callback groups: use `MutuallyExclusiveCallbackGroup` for hardware I/O, `ReentrantCallbackGroup` for independent subscribers.
- Headers: always include the `<package/header.hpp>` form, never relative paths.

### Python
- Standard: Python 3.10+, type hints on all public functions.
- Naming: `snake_case` throughout; class names `PascalCase`.
- Nodes should subclass `rclcpp` Node via `rclpy.node.Node`.
- Use `self.get_logger()` for all logging.
- Avoid `rospy`-style spin patterns; prefer `rclpy.spin()` or `MultiThreadedExecutor`.

### Launch Files
- Use Python launch files (`.launch.py`) — not XML unless legacy interop is needed.
- Parameters must be loaded via `yaml_file` substitution, not inlined.
- Always expose `use_sim_time` as a launch argument.

---

## Simulation Conventions

### MuJoCo
- Models live in `simulation/mujoco/<robot_name>/`.
- Scene XML imports the robot model; never edit generated files directly.
- Use `mujoco.MjData` copy semantics for parallel environments.
- Fixed timestep: match physics `dt` to your control loop frequency.

### Gazebo
- Worlds in `simulation/gazebo/worlds/`, models in `simulation/gazebo/models/`.
- Use `ros_gz_bridge` for topic bridging; declare all bridges explicitly in launch.
- Always test with `use_sim_time:=true`.

### Isaac Sim
- Extensions live in `simulation/isaac/`.
- Use the ROS2 bridge extension; match `domain_id` to local environment.

---

## ML / VLA Deployment

### Model Pipeline
```
Training (PyTorch) → ONNX export → TensorRT engine (Jetson) → ROS2 inference node
```

- ONNX exports go to `ml_models/onnx/<model_name>/`.
- TensorRT engines go to `ml_models/trt/<model_name>/<jetson_platform>/`.
- Never commit model weights > 50 MB to git; use DVC or LFS.
- Inference nodes must publish latency metrics on `/diagnostics`.

### VLA Specifics
- Action spaces: always validate Cartesian poses before IK; check workspace limits.
- Use behavior trees (BehaviorTree.CPP v4) to wrap VLA policies with safety middleware.
- Recovery behaviors must be isolated from the main feedback/control path.
- Log VLA inputs (image, instruction, proprio) at DEBUG level for debugging.

---

## Hardware / Embedded (Jetson)

- Target OS: JetPack 6.x (Ubuntu 22.04 base).
- Use `jetson-containers` as the base Docker image where possible.
- Power mode: set via `nvpmodel` before benchmarking; document the mode used.
- Always profile with `nsys` / `nvtop` before claiming performance numbers.
- GPIO / I2C: use `Jetson.GPIO` or direct `libgpiod`; avoid `RPi.GPIO` compatibility shims.
- CAN bus: use `python-can` with `socketcan` interface.

---

## Testing

- C++: `ament_cmake_gtest` for unit tests, `launch_testing` for integration.
- Python: `pytest` with `ament_pytest`.
- Every new node must have at minimum: a parameter loading test and a basic pub/sub smoke test.
- Mocking hardware: use `fake_hardware` in `ros2_control` or stub publishers.

---

## Skills Available

Claude has access to focused skill files for specific tasks. Read the relevant skill
before generating code or performing diagnostics:

| Task | Skill file |
|---|---|
| Create / scaffold a new ROS2 package | `.claude/skills/ros2-package/SKILL.md` |
| Debug ROS2 nodes, topics, TF, time | `.claude/skills/ros2-debug/SKILL.md` |

To use a skill, read the SKILL.md file first, then follow its instructions precisely.

---

## Behavior Guidelines for Claude

1. **Always read the relevant skill file before scaffolding or debugging.** Don't guess at conventions.
2. **Ask for the ROS2 distro and target platform** if not obvious from context before generating CMakeLists or Dockerfiles.
3. **Never hallucinate package names.** If unsure whether a ROS2 package exists, say so and suggest checking `ros2 pkg list` or `apt-cache search ros-<distro>`.
4. **Prefer working code over complete code.** If a full implementation is too long, scaffold with TODO stubs and explain what each stub needs.
5. **Flag hardware assumptions explicitly.** If code assumes Jetson Orin vs AGX vs Nano, say so.
6. **Sim-to-real gaps:** whenever writing sim code, note what will need to change for real hardware (timing, sensor noise, coordinate frames).
7. **Safety first:** for any motion planning or VLA output, always include a validation layer. Never generate code that commands motion without a bounds check.
