# SKILL: ROS2 Debugging & Diagnostics

Read this file completely before starting any debugging session.

---

## What this skill covers

Systematic diagnosis of ROS2 runtime issues: nodes not starting, topics not flowing,
TF problems, time synchronization, parameter errors, launch failures, and hardware
interface faults. Also covers Jetson-specific and simulation-specific failure modes.

---

## Golden rule

**Never guess. Always inspect first.** Run the diagnostic commands below and report
exact output before drawing conclusions. Most ROS2 bugs are one of 10 known patterns.

---

## Triage checklist — run these first

```bash
# 1. Are nodes running?
ros2 node list

# 2. Any crashes or errors?
ros2 node info /<node_name>

# 3. Topics publishing?
ros2 topic list
ros2 topic hz /topic_name
ros2 topic echo /topic_name --once

# 4. TF tree healthy?
ros2 run tf2_tools view_frames   # generates frames.pdf
ros2 run tf2_ros tf2_echo <parent> <child>

# 5. Parameters loaded?
ros2 param list /<node_name>
ros2 param get /<node_name> <param_name>

# 6. Services alive?
ros2 service list
ros2 service call /service_name <type> '{}'

# 7. Any active errors?
ros2 topic echo /diagnostics --once

# 8. colcon build clean?
colcon build --symlink-install 2>&1 | grep -E "error|warning|failed"
```

---

## Pattern library — the 10 most common failures

### Pattern 1: Node exits immediately / "process has died"

**Symptoms:** Node appears briefly in `ros2 node list` then disappears. Launch file says `process has died`.

**Diagnosis:**
```bash
# Run node directly (not via launch) to see stderr
ros2 run <pkg> <executable> --ros-args -p use_sim_time:=false

# Check for missing shared libraries
ldd $(ros2 pkg prefix <pkg>)/lib/<pkg>/<executable>

# Check colcon build log
cat log/latest_build/<pkg>/stdout_stderr.log
```

**Common causes & fixes:**
- Segfault on init: usually a `nullptr` dereference before `rclcpp::init()` completes. Move all initialization inside the constructor *after* `Node()` base init.
- Missing `rclcpp::init(argc, argv)` in `main()`.
- Python: `ModuleNotFoundError` — check `install/` directory was sourced: `. install/setup.bash`.
- Shared library not found: rebuild with `--cmake-clean-cache` or check `LD_LIBRARY_PATH`.

---

### Pattern 2: Topic not receiving data

**Symptoms:** Subscriber callback never fires. `ros2 topic hz` shows 0 Hz.

**Diagnosis:**
```bash
ros2 topic info /topic_name -v  # shows publishers, subscribers, QoS profiles
ros2 topic echo /topic_name
ros2 topic pub /topic_name <msg_type> '{...}' --once  # test subscriber directly
```

**Common causes & fixes:**
- **QoS mismatch** (most common): publisher and subscriber have incompatible QoS.
  Check `ros2 topic info -v` — RELIABILITY and DURABILITY must be compatible.
  Fix: match QoS or use `rclcpp::SensorDataQoS()` for sensor topics.
- **Namespace mismatch**: node is in `/robot1/` namespace but subscriber listens to `/topic` not `/robot1/topic`.
  Fix: use relative topic names or check launch file namespace args.
- **Remapping**: check launch file for `remappings` that redirect the topic.
- **Callback group blocking**: if using `MutuallyExclusiveCallbackGroup`, a blocking callback starves others.
  Fix: use `MultiThreadedExecutor` + `ReentrantCallbackGroup` for independent callbacks.

---

### Pattern 3: TF transform not found / extrapolation error

**Symptoms:** `"Could not find transform"`, `"Lookup would require extrapolation"`.

**Diagnosis:**
```bash
ros2 run tf2_tools view_frames   # is the frame in the tree at all?
ros2 run tf2_ros tf2_echo world base_link  # test specific transform
ros2 topic hz /tf /tf_static      # is TF being published?

# Check for disconnected subtrees
ros2 run tf2_tools view_frames && evince frames.pdf
```

**Common causes & fixes:**
- **Broken chain**: a frame in between is not being published. Find the gap in `frames.pdf`.
- **`use_sim_time` mismatch**: TF publisher uses wall clock, TF listener uses sim time.
  Fix: ensure ALL nodes in the chain have `use_sim_time:=true` when in simulation.
- **Extrapolation**: transform requested for a time outside the TF buffer window (default 10s).
  Fix: increase buffer duration in listener, or reduce latency in the publishing node.
- **Static vs dynamic**: if the transform is fixed, use `tf2_ros::StaticTransformBroadcaster` and publish once. Using dynamic broadcaster for static TF causes gaps.
- **Frame ID typo**: `"base_link"` vs `"base_link "` (trailing space). Check `ros2 topic echo /tf`.

---

### Pattern 4: Parameter not taking effect

**Symptoms:** Node starts but uses wrong values; YAML file seems ignored.

**Diagnosis:**
```bash
ros2 param list /<node_name>
ros2 param get /<node_name> <param_name>
# Compare against your YAML file
```

**Common causes & fixes:**
- **YAML structure wrong**: must be `<node_name>: ros__parameters: <params>`. The node name must match exactly what the node registers as (check `ros2 node list`).
- **YAML not installed**: `config/` directory not installed in CMakeLists. Verify `install(DIRECTORY config ...)` is present.
- **Wrong node name in YAML**: if node is launched as `my_node` but YAML uses `my_node_1`, params won't load.
- **Parameter declared after being read**: always `declare_parameter()` before `get_parameter()`.
- **Launch file not passing params file**: check `parameters=[params_file]` is in the `Node()` action.

---

### Pattern 5: `colcon build` fails

**Diagnosis:**
```bash
colcon build --symlink-install --event-handlers console_cohesion+ 2>&1 | tail -50

# Build single package with verbose output
colcon build --packages-select <pkg> --cmake-args -DCMAKE_VERBOSE_MAKEFILE=ON
```

**Common causes & fixes:**
- **Dependency not found**: `find_package(<dep> REQUIRED)` fails. Check `package.xml` has `<depend><dep></depend>`, and dep is installed: `apt list --installed | grep ros-<distro>-<dep>`.
- **Header not found**: check `ament_target_dependencies()` includes the package providing the header.
- **Python import error at colcon time**: missing `__init__.py` in Python module directory.
- **`install/` stale**: after renaming executables or packages, delete `build/` and `install/` and rebuild.

---

### Pattern 6: `use_sim_time` issues (simulation)

**Symptoms:** nodes running but nothing moves; timing-related callbacks never fire; TF extrapolation errors.

**Diagnosis:**
```bash
ros2 topic hz /clock        # must be publishing in sim
ros2 param get /<node> use_sim_time  # check each node
ros2 run tf2_ros tf2_echo world base_link  # TF lag hints at time issues
```

**Fix:**
- Every node must be launched with `use_sim_time:=true`.
- The sim (Gazebo/Isaac/MuJoCo bridge) must publish `/clock`.
- Do not mix `rclcpp::Clock(RCL_SYSTEM_TIME)` and `RCL_ROS_TIME` in the same pipeline.

---

### Pattern 7: ros2_control hardware interface not activating

**Symptoms:** controllers fail to start; `ros2 control list_hardware_interfaces` shows UNCONFIGURED or INACTIVE.

**Diagnosis:**
```bash
ros2 control list_controllers
ros2 control list_hardware_interfaces
ros2 topic echo /controller_manager/robot_description --once
journalctl -u ros2_control  # if running as systemd service
```

**Common causes & fixes:**
- **URDF not loaded**: controller manager needs robot_description param. Check `robot_state_publisher` is running.
- **Hardware plugin not found**: `pluginlib` can't find `<plugin>`. Check `export` block in plugin's `package.xml` and that package is built.
- **Interface name mismatch**: URDF `<joint name="...">` must exactly match controller YAML `joints: [...]`.
- **Activation order**: activate hardware interface before loading controllers.

---

### Pattern 8: High CPU / memory on Jetson

**Symptoms:** node running slowly, dropping messages, thermal throttling.

**Diagnosis:**
```bash
nvtop                  # GPU utilization
tegrastats             # CPU, GPU, memory, temperature, power
sudo nvpmodel -q       # current power mode
jtop                   # comprehensive Jetson monitor (pip install jetson-stats)
ros2 topic hz /topic   # is it keeping up?
```

**Fix:**
- Set max performance mode: `sudo nvpmodel -m 0 && sudo jetson_clocks`
- Check Docker `--runtime nvidia` and `--gpus all` flags if running in container.
- For inference nodes: ensure TensorRT engine is built for the correct Jetson platform (don't copy engines across devices).
- Use `RCLCPP_INFO_THROTTLE` instead of `RCLCPP_INFO` in high-frequency callbacks.

---

### Pattern 9: Launch file silent failure

**Symptoms:** `ros2 launch` completes with no error but expected nodes aren't running.

**Diagnosis:**
```bash
ros2 launch <pkg> <launch_file> --show-args  # list available args
ros2 launch <pkg> <launch_file> -d           # debug mode, shows event system
ros2 node list  # what actually started?
```

**Common causes & fixes:**
- **IfCondition / UnlessCondition**: a node is wrapped in a condition that evaluated to skip it. Trace the condition logic.
- **SetEnvironmentVariable** not applied before node: ordering matters in launch descriptions.
- **Included launch file path wrong**: `PathJoinSubstitution` resolved to a nonexistent file. Add `output='screen'` to included launches to surface errors.
- **Executable name wrong**: check exact executable name in CMakeLists `add_executable()` / setup.py `console_scripts`.

---

### Pattern 10: Message type mismatch / deserialization error

**Symptoms:** `ros2 topic echo` crashes; callback receives garbage data; C++ dynamic_cast fails.

**Diagnosis:**
```bash
ros2 topic info /topic_name    # check actual message type
ros2 interface show <msg_type>  # inspect message definition
ros2 topic echo /topic_name --message-type <type>  # force type
```

**Common causes & fixes:**
- Publisher and subscriber use different versions of a custom message. Rebuild both packages: `colcon build --packages-select <msgs_pkg> <node_pkg>`.
- Wrong `#include` path in C++ node — including old message type that happens to share field names.
- After changing a `.msg` file, always clean build: `rm -rf build/<msgs_pkg> install/<msgs_pkg>`.

---

## Simulation-specific debugging

### Gazebo
```bash
# Check Gazebo is actually running
gz sim --version
ps aux | grep gz

# Bridge topics
ros2 run ros_gz_bridge parameter_bridge /topic@std_msgs/msg/String@gz.msgs.StringMsg

# Model not appearing
gz topic -l  # list Gazebo-side topics
gz topic -e -t /world/<world_name>/model/<model>/link/<link>/sensor/<sensor>/image
```

### MuJoCo
```python
# Verify model loaded correctly
import mujoco
model = mujoco.MjModel.from_xml_path('model.xml')
print(f"nq={model.nq}, nv={model.nv}, nu={model.nu}")  # sanity check DOFs
data = mujoco.MjData(model)
mujoco.mj_step(model, data)  # step once — crashes = model error
```

### Isaac Sim
- Check ROS2 bridge extension is enabled in Extension Manager.
- Domain ID: `export ROS_DOMAIN_ID=0` must match Isaac's bridge config.
- Clock: enable "Publish Clock" in ROS2 bridge config.

---

## VLA / ML inference debugging

```bash
# Node receiving images?
ros2 topic hz /camera/image_raw

# Check inference latency
ros2 topic echo /diagnostics | grep -A5 "inference"

# TensorRT engine mismatch
python3 -c "import tensorrt as trt; print(trt.__version__)"
# Compare against engine build version in ml_models/trt/<model>/

# Check action output bounds
ros2 topic echo /vla/action_output --once
# Verify Cartesian poses are within workspace bounds before IK
```

---

## Useful one-liners

```bash
# Watch all topics and their frequencies
ros2 topic list | xargs -I{} sh -c 'echo {} && ros2 topic hz {} --once 2>/dev/null' 

# Find what's publishing to a topic
ros2 topic info /topic_name -v | grep "Publisher count" -A 20

# Dump all parameters for all nodes
ros2 param dump --all

# Trace message path end-to-end
ros2 run rqt_graph rqt_graph

# Record and replay for offline debugging
ros2 bag record -a -o debug_session
ros2 bag play debug_session/ --loop

# Check if a package is installed
ros2 pkg list | grep <pkg_name>

# Show complete node graph
rqt_graph &
```

---

## When escalating a bug report

If you need to ask for help (GitHub issue, forum), always include:
1. ROS2 distro and OS version: `ros2 doctor --report`
2. Exact error message (full stack trace, not paraphrased)
3. Output of `ros2 node list`, `ros2 topic list`
4. `ros2 topic info -v` for the relevant topic
5. The minimal reproducer — not your entire codebase
