# Device Info Fix Magisk Module

<div align="center">

**专为混刷系统包用户设计的设备信息修正模块**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Magisk](https://img.shields.io/badge/Magisk-20%2B-00B39B?logo=magisk)](https://github.com/topjohnwu/Magisk)
[![Android](https://img.shields.io/badge/Android-10%2B-3DDC84?logo=android)](https://www.android.com/)

</div>

---

## 📖 项目简介

本项目提供一个轻量级的 Magisk 模块，通过 **动态 bind-mount（推荐）/ RRO（备用）** 与 **system.prop** 覆盖机制，修正混刷系统包后的设备信息显示问题。

### 🎯 适用场景

✅ **混刷系统包场景**：底包和驱动正确，但系统镜像来自其他机型  
✅ **更换大容量电池**：系统显示电池容量不准确  
✅ **跨区域刷机**：设置中显示的机型名称、品牌与实际硬件不符  
✅ **定制 ROM 优化**：调整屏幕 DPI 以获得更好的显示效果  

### ⚡ 核心特性

- 🔋 **電池容量修正**：優先動態查找並 bind-mount 修補實際 `power_profile.xml`（僅替換 `battery.capacity`），並保留 RRO 作為備用
- 📱 **設備標識覆蓋**：修正機型名稱、品牌、製造商等顯示資訊
- 🖥️ **CPU 名稱覆蓋**：透過 RRO overlay 修正「設置 → 關於手機」中的處理器名稱顯示
- 🎨 **螢幕密度調整**：自定義 DPI 以優化顯示效果
- ✅ **参数校验保护**：自动验证输入参数，防止配置错误
- 🚀 **自动化构建**：GitHub Actions 云端构建或本地脚本一键打包
- 🔒 **签名安全**：使用标准 Android 签名流程，确保模块可信

---

## 🛡️ 安全性说明

### ✅ 安全可修改的属性

本模块**仅修改显示层面和软件识别层面**的属性，不涉及底层硬件接口：

| 属性类别 | 说明 | 影响范围 |
|---------|------|---------|
| **电池容量** | 修正电量百分比计算和显示 | 系统设置、状态栏、电池管理 |
| **设备标识** | 机型名称、设备 ID、品牌 | 系统信息显示、应用兼容性识别 |
| **屏幕密度** | DPI 显示缩放 | UI 元素大小、布局 |

### ⚠️ 不建议修改的属性

| 属性类型 | 为什么不建议修改 | 风险 |
|---------|----------------|------|
| **CPU 信息** | 从 `/proc/cpuinfo` 硬件直接读取 | 性能优化错误、应用崩溃 |
| **RAM 大小** | 从内核 `/proc/meminfo` 读取 | prop 覆盖无效且可能引起兼容性问题 |
| **硬件序列号** | 涉及设备唯一标识 | 可能影响授权验证、设备管理 |
| **指纹/安全属性** | 涉及系统安全验证 | 可能导致 SafetyNet 失败、系统不稳定 |

**原则**：底包和驱动已正确的情况下，只修正"软件层面的显示问题"，不触碰硬件层面的属性。

---

## 📋 支持的参数

### 1. 电池容量 (`battery_capacity`)

**说明**：修正系统识别的电池容量（单位：mAh）  
**实现**：仅当设置了 `battery_capacity` 时才会启用电池修正：开机后自动查找真实的 `power_profile.xml` 路径（例如某些机型在 `/odm/etc/power_profile/power_profile.xml`），生成一份“仅替换 `battery.capacity`”的完整副本并 `mount --bind` 覆盖；同时可选打包 RRO overlay 作为兼容性备用。  
**示例**：`5000`、`4500`、`6000`  
**验证规则**：必须是 1000-20000 之间的正整数  
**适用场景**：更换大容量电池、混刷系统包导致电量显示不准  
**安全性**：不写入分区；禁用/卸载并重启后自动还原（卸载时也会尝试主动 `umount`）

**重要**：若未設置 `battery_capacity`，模組不會打包/啟用任何電池覆蓋功能，系統將保持原廠容量（符合「除非被要求，否則不更改硬體資訊」的原則）。

```bash
# 环境变量方式（本地构建）
export BATTERY_CAPACITY=5000
```

---

### 1.5 CPU 名稱 (`cpu_name`)

**說明**：透過 RRO overlay 覆蓋「設置 → 關於手機 → 處理器」中顯示的 CPU 名稱  
**實現**：編譯一個簽名的 overlay APK (`cpu-overlay.apk`)，目標包為 `com.android.settings`，覆蓋字串資源 `device_info_processor`  
**示例**：`Snapdragon 8s Gen3`、`Dimensity 9200`、`Snapdragon 8 Gen 3`  
**適用場景**：混刷後處理器名稱顯示不正確，或某些 ROM 缺少處理器資訊顯示  
**注意**：此功能僅影響「設置」應用中的顯示，不影響系統識別或性能

**重要**：若未設置 `cpu_name`，模組不會打包 CPU overlay，系統將保持原本的處理器名稱顯示。

```bash
# 环境变量方式（本地构建）
export CPU_NAME="Snapdragon 8s Gen3"
```

---

### 2. 设备 ID (`device_id`)

**说明**：设备代号（仅显示用途，不修改 `ro.product.device`）  
**示例**：`alioth`、`munch`、`sweet`  
**验证规则**：只能包含字母、数字、连字符和下划线  
**适用场景**：混刷后设备代号显示错误

```bash
# 环境变量方式
export DEVICE_ID=alioth
```

**覆盖的属性**：
- `ro.product.device.display`
- `ro.vendor.product.device.display`

---

### 3. 机型名称 (`model_name`)

**说明**：覆盖 `ro.product.model`（设置中显示的机型名称）  
**示例**：`Redmi K40`、`Mi 11 Ultra`、`POCO F3`  
**适用场景**：设置 → 关于手机中显示的名称不正确  
**安全性**：自动过滤换行符、等号、Shell 元字符，防止注入攻击

```bash
# 环境变量方式
export MODEL_NAME="Redmi K40"
```

**额外功能 - 设备名称覆盖**：
- 当设置 `model_name` 时，模块还会自动覆盖系统的 `device_name` 设置
- 这会影响**蓝牙显示名称**、**热点名称**等
- 仅在模块安装/更新后的**首次重启**时应用（不会每次重启都覆盖）
- 用户可以在应用后手动修改为其他名称

**回滚行为**：
- **禁用模块**：下次重启时自动检测 `disable` 标记并还原为系统默认值
- **卸载模块**：安装脚本中执行 `settings delete` 还原
- **注意**：这是持久化设置，禁用后必须重启才能回滚

**覆盖的属性**：
- `ro.product.model`
- `ro.product.system.model`
- `ro.product.vendor.model`

---

### 4. 品牌名称 (`brand`)

**说明**：覆盖 `ro.product.brand`（品牌标识）  
**示例**：`Redmi`、`Xiaomi`、`POCO`  
**适用场景**：品牌信息显示不正确

```bash
# 环境变量方式
export BRAND=Redmi
```

**覆盖的属性**：
- `ro.product.brand`
- `ro.product.system.brand`
- `ro.product.vendor.brand`

---

### 5. 制造商 (`manufacturer`)

**说明**：覆盖 `ro.product.manufacturer`（制造商）  
**示例**：`Xiaomi`、`OnePlus`、`Samsung`  
**适用场景**：制造商信息显示不正确

```bash
# 环境变量方式
export MANUFACTURER=Xiaomi
```

**覆盖的属性**：
- `ro.product.manufacturer`
- `ro.product.system.manufacturer`
- `ro.product.vendor.manufacturer`

---

### 6. 屏幕密度 (`lcd_density`)

**说明**：覆盖 `ro.sf.lcd_density`（屏幕 DPI）  
**示例**：`440`、`480`、`560`  
**验证规则**：必须是 120-640 之间的正整数  
**适用场景**：优化显示效果、UI 元素大小调整

```bash
# 环境变量方式
export LCD_DENSITY=440
```

**常见 DPI 参考**：
- `320` - mdpi（中密度）
- `480` - xxhdpi（超高密度）
- `560` - xxxhdpi（超超高密度）

**覆盖的属性**：
- `ro.sf.lcd_density`

---

### 7. 产品名称 (`product_name`)

**说明**：覆盖 `ro.product.name`（产品内部名称）  
**示例**：`PLQ110`、`CPH2767IN`、`alioth_global`  
**验证规则**：只能包含字母、数字、连字符和下划线  
**适用场景**：混刷后产品名称与实际硬件不符，某些应用或服务依赖此属性识别设备

```bash
# 环境变量方式
export PRODUCT_NAME=PLQ110
```

**覆盖的属性**：
- `ro.product.name`
- `ro.product.system.name`
- `ro.product.vendor.name`

**注意**：此属性通常与 `ro.build.product` 配合使用，某些系统服务可能会检查两者是否匹配。

---

### 8. 构建产品名 (`build_product`)

**说明**：覆盖 `ro.build.product`（构建时的产品标识）  
**示例**：`OP612DL1`、`alioth`、`sweet`  
**验证规则**：只能包含字母、数字、连字符和下划线  
**适用场景**：某些应用检查构建产品名与设备 ID 是否一致，混刷后可能不匹配

```bash
# 环境变量方式
export BUILD_PRODUCT=OP612DL1
```

**覆盖的属性**：
- `ro.build.product`

**注意**：此属性通常应与 `device_id` 保持一致，以避免兼容性问题。

---

### 9. 音量曲线优化 (`optimize_volume`)

**说明**：启用扬声器音量曲线线性化优化  
**类型**：布尔值（`true` / `false`）  
**默认**：`false`（禁用）  
**实现**：通过 bind-mount 替换系统音频配置文件中的 `DEFAULT_DEVICE_CATEGORY_SPEAKER_VOLUME_CURVE`  
**适用场景**：某些设备的扬声器音量曲线过于激进，导致低音量时声音变化不明显，高音量时突然变大  

```bash
# 环境变量方式
export OPTIMIZE_VOLUME=true
```

**技术细节**：
- 自动搜索 `/vendor/etc/`、`/odm/etc/`、`/system/etc/` 下的音频配置文件
- 使用 13 点线性音量曲线替换原有的扬声器音量曲线
- bind-mount 方式不修改原文件，禁用/卸载模块并重启后自动还原

**线性曲线点位**：
| 音量级别 | dB 增益 |
|---------|--------|
| 1%      | -60.0 dB |
| 5%      | -52.0 dB |
| 10%     | -46.0 dB |
| 15%     | -41.0 dB |
| 20%     | -36.0 dB |
| 30%     | -30.0 dB |
| 40%     | -25.0 dB |
| 50%     | -20.0 dB |
| 60%     | -16.0 dB |
| 70%     | -12.0 dB |
| 80%     | -8.0 dB |
| 90%     | -4.0 dB |
| 100%    | 0 dB |

**安全性**：仅影响扬声器外放，不影响耳机/蓝牙音频

---

### 10. 最低亮度限制 (`brightness_floor`)

**说明**：防止自动亮度在极暗环境下将屏幕亮度调至全黑  
**类型**：布尔值（`true` / `false`）  
**默认**：`false`（禁用）  
**实现**：通过写入 sysfs 节点设置最低亮度/alpha 值，不使用 bind-mount  
**适用场景**：某些设备在夜间或暗室环境下，自动亮度会将屏幕调至完全黑色，无法看清内容

```bash
# 环境变量方式
export BRIGHTNESS_FLOOR=true
```

**支持的设备/ROM**：

| 厂商 | ROM | 实现方式 |
|-----|-----|---------|
| OPLUS / realme / OnePlus | ColorOS / OxygenOS | 禁用 `dimlayer_bl_en`，设置 `dim_alpha` 下限 200 |
| 小米 / 红米 | MIUI / HyperOS | 设置 `dim_alpha` / `dc_alpha` 下限 200 |
| 三星 | OneUI | 设置 backlight brightness 最低值 5 |
| Pixel / AOSP / LineageOS | 通用 | 遍历所有 backlight 节点设置最低值 5 |

**技术细节**：
- 自动检测设备类型，按优先级尝试各厂商专用节点（成功后停止）
- alpha 值 200 = 夜间可读但不刺眼的亮度
- brightness 值 5 = 最低可见亮度（三星/通用）
- 仅写入 sysfs 运行时节点，不修改任何持久化文件

**回滚行为**：
- sysfs 节点是内核运行时状态，**重启后自动恢复系统默认值**
- 禁用模块：下次重启后 service.sh 不执行，亮度限制自动失效
- 卸载模块：同上，重启后完全恢复

**安全性**：
- lux 传感器仍正常参与亮度计算
- 白天/室内/户外亮度完全不受影响
- 仅限制"自动亮度计算结果的最小值"

---

## 🚀 使用步骤

### 方式一：GitHub Actions（推荐）

#### 首次配置（仅需一次）

1. **生成签名密钥**（如果还没有）：

```bash
keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias my-alias
```

2. **将密钥转换为 Base64**：

```bash
# Linux/macOS
base64 release.jks | tr -d '\n' > release.jks.base64

# Windows PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("release.jks")) | Out-File -Encoding ASCII release.jks.base64
```

3. **在 GitHub 仓库中添加 Secrets**：

前往 `Settings` → `Secrets and variables` → `Actions` → `New repository secret`

| Secret 名称 | 说明 | 示例 |
|------------|------|------|
| `SIGNING_KEY` | Base64 编码的 `release.jks` | （从 `release.jks.base64` 文件复制） |
| `ALIAS` | 密钥别名 | `my-alias` |
| `KEY_STORE_PASSWORD` | 密钥库密码 | 创建密钥时设置的密码 |
| `KEY_PASSWORD` | 密钥密码 | 创建密钥时设置的密码 |

#### 构建模块

4. **触发构建**：

   - 进入仓库的 `Actions` 标签页
   - 选择 `Publish Release` workflow
   - 点击 `Run workflow`
   - 填写需要修改的参数（均为可选）

5. **下载模块**：

   - 等待构建完成（约 2-3 分钟）
   - 在 workflow 运行详情页面的 `Artifacts` 区域
   - 下载 `DeviceInfoFix*-Module.zip`

6. **安装模块**：

   - 打开 Magisk Manager
   - 点击 `模块` → `从本地安装`
   - 选择下载的 `DeviceInfoFix*-Module.zip`
   - 重启设备生效

---

### 方式二：本地构建

#### 环境要求

- **推荐平台**：Linux / Windows (WSL) / macOS (需 GNU 工具)
- Bash shell (4.0+)
- Android SDK（包含 `build-tools` 和 `platforms/android-33`）
- Java 17+

**重要注意 - 平台兼容性**：

1. **macOS/BSD 用户必须安装 GNU coreutils**：
   ```bash
   # macOS
   brew install coreutils
   
   # 确认 base64 支持 -d 参数（非 BSD 版本）
   which base64  # 应该显示 /usr/local/opt/coreutils/libexec/gnubin/base64
   ```
   
   或者使用 WSL/Docker 容器以获得更好的兼容性。

2. **Keystore 安全注意事项**：
   - 脚本会将 keystore 临时复制到 `build/` 目录，构建完成后自动清理
   - **不要**将项目目录放在同步盘（Dropbox/OneDrive）中
   - **不要**将 `release.jks` 提交到 Git 仓库（已在 `.gitignore` 中）
   - 优先使用环境变量 `SIGNING_KEY_B64` 传递密钥

#### 构建步骤

1. **设置 Android SDK 环境变量**：

```bash
export ANDROID_HOME=/path/to/android-sdk
```

2. **准备签名密钥**：

将 `release.jks` 放在项目根目录，或通过环境变量提供：

```bash
export SIGNING_KEY_B64="<base64-encoded-keystore>"
export ALIAS="my-alias"
export KEY_STORE_PASSWORD="your-password"
export KEY_PASSWORD="your-password"
```

3. **设置自定义参数**（可选）：

```bash
export BATTERY_CAPACITY=5000
export DEVICE_ID=alioth
export MODEL_NAME="Redmi K40"
export BRAND=Redmi
export MANUFACTURER=Xiaomi
export LCD_DENSITY=440
```

4. **执行构建脚本**：

```bash
bash build-overlay.sh
```

5. **安装生成的模块**：

构建完成后会生成 `DeviceInfoFix*-Module.zip`，通过 Magisk Manager 安装。

---

## 💡 使用示例

### 示例 1：仅修正电池容量

**场景**：更换了 5000mAh 的大容量电池，系统仍显示原厂 4500mAh

**参数配置**：
```
battery_capacity: 5000
```

**效果**：系统电量百分比计算准确，设置中显示正确容量

---

### 示例 2：修正混刷机型信息

**场景**：Redmi K40 刷了 POCO F3 的系统包，设置中显示 POCO F3

**参数配置**：
```
device_id: alioth
model_name: Redmi K40
brand: Redmi
manufacturer: Xiaomi
```

**效果**：
- 设置 → 关于手机 → 显示 "Redmi K40"
- 品牌显示为 "Redmi"
- 应用商店正确识别设备型号

---

### 示例 3：完整配置（电池 + 机型 + DPI）

**场景**：跨区域混刷 + 更换电池 + 优化显示

**参数配置**：
```
battery_capacity: 5000
device_id: alioth
model_name: Redmi K40
brand: Redmi
manufacturer: Xiaomi
lcd_density: 440
```

**效果**：
- ✅ 电池容量显示 5000mAh
- ✅ 机型显示正确
- ✅ UI 按 440 DPI 渲染，显示更清晰

---

### 示例 4：仅调整屏幕密度

**场景**：UI 元素太大或太小，希望调整显示缩放

**参数配置**：
```
lcd_density: 480
```

**效果**：系统 UI 按 480 DPI 重新渲染（重启后生效）

---

### 示例 5：完整配置所有参数（推荐用于跨区混刷）

**场景**：OnePlus Ace 6 刷入其他区域 ROM，需要完整修正设备信息

**参数配置**：
```
battery_capacity: 7800
device_id: OP612DL1
model_name: Ace 6
brand: OnePlus
manufacturer: OnePlus
lcd_density: 440
product_name: PLQ110
build_product: OP612DL1
cpu_name: Snapdragon 8s Gen3
```

**效果**：
- ✅ 电池容量显示 7800mAh（一加 Ace 6 的实际容量）
- ✅ 机型显示 "Ace 6"
- ✅ 产品名称和构建产品名与实际硬件一致
- ✅ 处理器名称显示 "Snapdragon 8s Gen3"
- ✅ 应用商店和系统服务正确识别设备
- ✅ 屏幕显示优化（440 DPI）

**说明**：
- `device_id` 和 `build_product` 通常应保持一致
- `product_name` 是内部标识，某些系统服务会检查
- `cpu_name` 仅影响设置中的显示，不影响性能调度
- 仅设置需要修正的参数，其他可留空使用系统默认值

---

### 示例 6：仅修正 CPU 名称

**场景**：ROM 的处理器名称显示不正确或缺失

**参数配置**：
```
cpu_name: Dimensity 9200
```

**效果**：「设置 → 关于手机 → 处理器」显示 "Dimensity 9200"

---

## 🔧 技术原理

### 1. 电池容量修正机制（时序关键）
    
**方案 A（核心）：动态 bind-mount (post-fs-data)**
这是唯一能够“欺骗” Android 系统服务的有效方式。
- **执行时机**：`post-fs-data.sh`（Zygote 启动前）
- **原理**：在此阶段挂载修改后的 `power_profile.xml`，当 `PowerManagerService` 随后启动并读取文件时，它已经是修改过的版本。
- **注意**：如果通过常规 `service.sh`（开机完成后）修改，系统服务已经读完了旧文件，修改将无效。

**方案 B（辅助）：RRO Overlay (service.sh)**
- **执行时机**：`service.sh`（开机完成后）
- **原理**：通过 `cmd overlay` 命令显式启用 overlay APK。因为 `cmd` 命令需要 System Server 运行后才能使用，所以必须放在 `service.sh` 中执行。
- **安装位置**：`/system/product/overlay/`（Android 10+ 标准路径）

### 2. CPU 名称修正机制 (Overlay)
由于 CPU 名称仅用于设置界面的显示（不被底层服务缓存），因此只需要 RRO overlay：
- 编译并安装 `cpu-overlay.apk` 到 `/system/product/overlay/`
- 在 `service.sh` 中通过 `cmd overlay enable` 确保其激活

### 3. 音量曲线优化 (post-fs-data)
与电池容量类似，音频策略服务在启动时读取配置文件。因此，音量曲线的 XML 修改和 bind-mount 也必须在 `post-fs-data` 阶段完成。

### system.prop 覆盖机制

Magisk 支持通过模块中的 `system.prop` 文件覆盖系统属性：

1. 模块中包含 `system.prop` 文件
2. Magisk 在启动时注入这些属性
3. 覆盖原有的 `ro.product.*` 属性

### 构建流程

```
输入参数 → 参数校验 → 生成 XML/Prop 文件 → 编译资源 → 签名 APK → 打包模块
```

**使用的工具**：
- `aapt2`：编译和链接 Android 资源
- `apksigner`：对 APK 进行签名
- `zip`：打包 Magisk 模块

---

## 📁 项目结构

```
FixDeviceInfo/
├── .github/
│   └── workflows/
│       └── release.yml              # GitHub Actions 自动化构建
├── overlay-src/                     # RRO overlay 模板源码
│   ├── battery/                     # 电池容量 overlay
│   │   ├── AndroidManifest.xml
│   │   └── res/xml/power_profile.xml.in
│   └── cpu/                         # CPU 名称 overlay
│       ├── AndroidManifest.xml
│       └── res/values/strings.xml.in
├── module/
│   ├── module.prop                  # Magisk 模块元数据
│   ├── service.sh                   # 主入口脚本（调度各功能模块）
│   ├── post-fs-data.sh              # 早期启动脚本
│   ├── uninstall.sh                 # 卸载清理脚本
│   ├── volume_curve_patch.xml       # 音量曲线补丁模板
│   ├── scripts/                     # 功能模块脚本（独立维护）
│   │   ├── common.sh                # 公共函数（日志、工具）
│   │   ├── battery.sh               # 电池容量覆盖
│   │   ├── volume.sh                # 音量曲线优化
│   │   ├── brightness.sh            # 最低亮度限制
│   │   └── device_name.sh           # 设备名称覆盖
│   └── META-INF/
│       └── com/google/android/
│           └── update-binary        # Magisk 安装脚本
├── build-overlay.sh                 # 本地构建脚本
└── README.md                        # 本文档
```

**模块化设计说明**：
- `service.sh` 仅负责调度，不包含具体功能实现
- 每个功能独立一个脚本，便于维护和调试
- `common.sh` 提供共享的日志和工具函数
- 功能脚本可独立测试（直接执行对应 .sh 文件）

**重要路径说明**：
- RRO overlay APK 安装到 `system/product/overlay/`（Android 10+ 标准路径）
- 旧版 `system/vendor/overlay/` 路径已弃用（部分 ROM 不加载）

---

## ❓ 常见问题

### Q1: 模块安装后没有生效？

**排查步骤**：
1. 确认在 Magisk Manager 中模块已启用
2. **必须重启设备**才能生效
3. 检查 Magisk 日志是否有报错
4. 运行 `getprop ro.product.model` 查看属性是否已覆盖

---

### Q2: 电池容量修改后电量显示异常？

**可能原因**：
- 输入的容量值与实际电池容量差异太大
- 需要完全充放电一次以重新校准电池统计

**建议**：
- 确保输入的容量值与实际电池铭牌一致
- 充电至 100% 后使用至 5% 以下，重复 2-3 次

---

### Q3: 可以同时安装多个类似模块吗？

**不建议**。多个模块修改相同属性可能冲突，请：
- 卸载其他修改设备信息的模块
- 使用本模块的多参数功能一次性配置所有需求

---

### Q4: 修改 DPI 后应用显示异常？

**解决方法**：
- 清除问题应用的数据缓存
- 部分应用不支持自适应 DPI，恢复默认值即可
- 尝试其他 DPI 值（推荐 420、440、480、560）

---

### Q5: 如何恢复原始设置？

**禁用模块**：
1. 在 Magisk Manager 中切换模块开关（禁用）
2. 重启设备
3. 各功能恢复行为：

| 功能 | 禁用后行为 | 是否需要重启 |
|------|-----------|-------------|
| 电池容量 (bind-mount) | bind-mount 失效，自动恢复 | ✅ 需要 |
| 音量曲线 (bind-mount) | bind-mount 失效，自动恢复 | ✅ 需要 |
| 亮度下限 (sysfs) | sysfs 值重置，自动恢复 | ✅ 需要 |
| 设备名称 (settings) | **运行时自动回滚** | ⚠️ 最好重启 |
| system.prop 属性 | Magisk 不再注入，自动恢复 | ✅ 需要 |

**设备名称特殊处理**：
- 模块运行时会轮询检测 `disable` 标记（每 2 秒）
- 检测到禁用后**立即执行 `settings delete`** 回滚
- 无需等待重启即可恢复（但建议重启以确保完全生效）

**卸载模块**：
1. 在 Magisk Manager 中删除模块
2. 卸载脚本会主动清理（`umount`、`settings delete` 等）
3. 重启后完全恢复原状

---

### Q6: 参数校验失败怎么办？

**示例错误**：
```
❌ Error: battery_capacity must be a positive integer
```

**解决方法**：
- 检查输入格式是否正确（必须是纯数字）
- 确认数值在合理范围内：
  - 电池容量：1000-20000 mAh
  - 屏幕密度：120-640 DPI
- 设备 ID 仅包含字母、数字、连字符和下划线

---

### Q7: 无参数构建会发生什么？

**说明**：如果构建时不提供任何设备信息参数（仅提供 `battery_capacity`），模块将：
- ✅ 正常安装 RRO overlay（电池容量修正）
- ⚠️ **不包含** `system.prop` 文件
- ℹ️ 安装时显示 "System properties: using defaults"

**Magisk 兼容性**：
- Magisk v20.4+ 完全支持此场景（`PROPFILE=true` 但 `system.prop` 缺失）
- 模块可以正常工作，只是不会覆盖设备信息属性
- 这是**正常设计行为**，不是错误

---

## 📚 参考资料

- [Magisk 官方文档](https://topjohnwu.github.io/Magisk/)
- [Android Runtime Resource Overlay](https://source.android.com/docs/core/runtime/rros)
- [Android 系统属性机制](https://source.android.com/docs/core/architecture/configuration/add-system-properties)

---

## 📄 许可证

本项目采用 MIT 许可证。详见 [LICENSE](LICENSE) 文件。

---
