# SKILL: ROS2 Package Scaffolding

Read this file completely before generating any ROS2 package structure or boilerplate.

---

## What this skill covers

Creating new ROS2 packages from scratch: directory layout, CMakeLists.txt, package.xml,
node boilerplate (C++ and Python), launch files, parameter YAML, and test stubs.

---

## Step-by-step process

### Step 1 — Gather requirements before writing any code

Ask (or infer from context) the following. Do not proceed until you have answers:

| Question | Why it matters |
|---|---|
| ROS2 distro? (Humble / Iron / Jazzy) | CMake minimum version, API differences |
| Language? (C++ / Python / mixed) | Determines build system setup |
| Node type? (standalone / component / lifecycle) | Different boilerplate |
| Does it use ros2_control? | Adds hardware_interface dependencies |
| Does it publish/subscribe or is it a service? | Interface generation setup |
| Custom messages/services needed? | Requires separate `_msgs` package |
| Target platform? (x86 / Jetson) | Affects dependencies and Docker base |

### Step 2 — Choose the correct build system setup

**C++ package (ament_cmake)**
```cmake
cmake_minimum_required(VERSION 3.8)
project(<pkg_name>)

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
# add other find_package() calls here

add_executable(<node_name> src/<node_name>.cpp)
ament_target_dependencies(<node_name> rclcpp <other_deps>)

install(TARGETS <node_name> DESTINATION lib/${PROJECT_NAME})
install(DIRECTORY launch config DESTINATION share/${PROJECT_NAME})

if(BUILD_TESTING)
  find_package(ament_lint_auto REQUIRED)
  ament_lint_auto_find_test_dependencies()
  find_package(ament_cmake_gtest REQUIRED)
  # add gtest targets here
endif()

ament_package()
```

**Python package (ament_python)**
```python
# setup.py
from setuptools import setup

package_name = '<pkg_name>'
setup(
    name=package_name,
    version='0.1.0',
    packages=[package_name],
    data_files=[
        ('share/ament_index/resource_index/packages', ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        ('share/' + package_name + '/launch', ['launch/<node>.launch.py']),
        ('share/' + package_name + '/config', ['config/params.yaml']),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    entry_points={
        'console_scripts': [
            '<node_name> = <pkg_name>.<node_name>:main',
        ],
    },
)
```

**Mixed C++/Python:** use `ament_cmake` as the build type and add a `<pkg_name>/` Python module
directory. Install Python scripts via `ament_python_install_package()` in CMakeLists.

### Step 3 — Generate package.xml

```xml
<?xml version="1.0"?>
<?xml-model href="http://download.ros.org/schema/package_format3.xsd" schematypens="http://www.w3.org/2001/XMLSchema"?>
<package format="3">
  <name><pkg_name></name>
  <version>0.1.0</version>
  <description>TODO: Package description</description>
  <maintainer email="your@email.com">Your Name</maintainer>
  <license>Apache-2.0</license>

  <buildtool_depend>ament_cmake</buildtool_depend>  <!-- or ament_python -->

  <depend>rclcpp</depend>  <!-- add actual deps -->

  <test_depend>ament_lint_auto</test_depend>
  <test_depend>ament_lint_common</test_depend>

  <export>
    <build_type>ament_cmake</build_type>  <!-- or ament_python -->
  </export>
</package>
```

### Step 4 — Node boilerplate

**C++ standalone node**
```cpp
// src/<node_name>.cpp
#include "<pkg_name>/<node_name>.hpp"

namespace <pkg_name>
{

<NodeName>::<NodeName>(const rclcpp::NodeOptions & options)
: Node("<node_name>", options)
{
  // Declare all parameters first
  this->declare_parameter("example_param", 1.0);
  example_param_ = this->get_parameter("example_param").as_double();

  // QoS
  auto qos = rclcpp::QoS(rclcpp::KeepLast(10));

  // Publishers / subscribers
  publisher_ = this->create_publisher<std_msgs::msg::String>("output", qos);
  subscriber_ = this->create_subscription<std_msgs::msg::String>(
    "input", qos,
    std::bind(&<NodeName>::topic_callback, this, std::placeholders::_1));

  RCLCPP_INFO(this->get_logger(), "<NodeName> initialized");
}

void <NodeName>::topic_callback(const std_msgs::msg::String::SharedPtr msg)
{
  // TODO: implement
  (void)msg;
}

}  // namespace <pkg_name>

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<<pkg_name>::<NodeName>>(rclcpp::NodeOptions{}));
  rclcpp::shutdown();
  return 0;
}
```

**C++ lifecycle node** — use when the node controls hardware that needs managed startup/shutdown:
```cpp
#include "rclcpp_lifecycle/lifecycle_node.hpp"

class <NodeName> : public rclcpp_lifecycle::LifecycleNode
{
  // Override: on_configure, on_activate, on_deactivate, on_cleanup, on_shutdown
};
```

**Python standalone node**
```python
# <pkg_name>/<node_name>.py
import rclpy
from rclpy.node import Node
from std_msgs.msg import String


class <NodeName>(Node):
    def __init__(self) -> None:
        super().__init__('<node_name>')

        # Declare parameters
        self.declare_parameter('example_param', 1.0)
        self.example_param = self.get_parameter('example_param').value

        self.publisher_ = self.create_publisher(String, 'output', 10)
        self.subscription = self.create_subscription(
            String, 'input', self.listener_callback, 10)

        self.get_logger().info('<NodeName> initialized')

    def listener_callback(self, msg: String) -> None:
        # TODO: implement
        pass


def main(args=None) -> None:
    rclpy.init(args=args)
    node = <NodeName>()
    rclpy.spin(node)
    node.destroy_node()
    rclpy.shutdown()


if __name__ == '__main__':
    main()
```

### Step 5 — Launch file

```python
# launch/<node_name>.launch.py
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration, PathJoinSubstitution
from launch_ros.actions import Node
from launch_ros.substitutions import FindPackageShare


def generate_launch_description() -> LaunchDescription:
    use_sim_time = LaunchConfiguration('use_sim_time', default='false')
    params_file = PathJoinSubstitution([
        FindPackageShare('<pkg_name>'), 'config', 'params.yaml'
    ])

    return LaunchDescription([
        DeclareLaunchArgument('use_sim_time', default_value='false',
                              description='Use simulation clock'),

        Node(
            package='<pkg_name>',
            executable='<node_name>',
            name='<node_name>',
            output='screen',
            parameters=[params_file, {'use_sim_time': use_sim_time}],
        ),
    ])
```

### Step 6 — Parameter YAML

```yaml
# config/params.yaml
<node_name>:
  ros__parameters:
    example_param: 1.0
    # add all declared parameters here with sensible defaults
```

**Rule:** every `declare_parameter()` call in the node must have a corresponding entry here.

### Step 7 — Test stubs

```cpp
// test/test_<node_name>.cpp
#include <gtest/gtest.h>
#include "rclcpp/rclcpp.hpp"

TEST(TestNodeParams, LoadsDefaults) {
  rclcpp::init(0, nullptr);
  // TODO: instantiate node and verify parameters loaded
  rclcpp::shutdown();
}

int main(int argc, char ** argv) {
  testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
```

---

## Custom message packages

If the user needs custom msgs/srvs/actions, create a separate `<project>_msgs` package:

```
<project>_msgs/
├── msg/
│   └── MyMessage.msg
├── srv/
│   └── MyService.srv
├── action/
│   └── MyAction.action
├── CMakeLists.txt   # uses rosidl_generate_interfaces()
└── package.xml
```

**Critical CMake for msg package:**
```cmake
find_package(rosidl_default_generators REQUIRED)
rosidl_generate_interfaces(${PROJECT_NAME}
  "msg/MyMessage.msg"
  DEPENDENCIES std_msgs geometry_msgs
)
ament_export_dependencies(rosidl_default_runtime)
```

---

## Common mistakes to avoid

- **Never** add `rosidl_generate_interfaces` to a package that also contains nodes — keep msgs separate.
- **Never** forget `ament_export_dependencies` in a library package or downstream builds will fail.
- **Always** install the `config/` and `launch/` directories or `FindPackageShare` won't find them.
- **C++ headers** must be installed to `include/${PROJECT_NAME}/` for other packages to find them.
- **Python packages** need the `resource/<pkg_name>` marker file for `ament_index` registration.

---

## Quality checklist before presenting generated code

- [ ] `package.xml` lists all `<depend>` entries for every `find_package` in CMakeLists
- [ ] All parameters declared in node are present in `config/params.yaml`
- [ ] Launch file has `use_sim_time` argument
- [ ] Node uses `RCLCPP_INFO/WARN/ERROR` — no `std::cout` or `print()`
- [ ] Test stub created and added to CMakeLists `if(BUILD_TESTING)` block
- [ ] `install()` calls cover `launch/`, `config/`, headers, and executables
