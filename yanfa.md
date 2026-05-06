夏日萤火 —— 本地离线 Mesh 组网通讯 APP 完整研发文档

软件定位：iPhone 去中心化离线 Mesh 自组网工具，支持蓝牙/WiFi 双介质、多跳中继路由、端到端加密、一机一ID、积分激励、等高线离线地图、路径寻址与导航。

一、产品概述

1.1 产品名称

夏日萤火

1.2 核心定位

基于 iPhone 构建纯本地无线 Mesh 自组织网络，在无运营商网络、无外网环境下，实现：

• 多设备语音实时互传

• 离线等高线地图 + GPS 位置共享

• 多跳中继路由（A→B→C 远距离传输）

• 端到端非对称加密（公钥/私钥身份验证）

• 一机一ID 唯一身份 + 可自定义不重复用户名

• 积分激励体系（转发越多积分越高、连接越优先）

• 双运行模态：待机中继 / 面对面组网建群

• 蓝牙 / WiFi 手动切换通信介质

• 路径式离线地图下载 + 自动路径寻址导航

1.3 适用场景

• 户外徒步、山地穿越

• 应急救援、无信号区域通讯

• 大型集会、团队协作

• 野外勘探、地形导航

• 家族/社群近距离私密通讯

1.4 核心术语

• 节点：每台安装 APP 的 iPhone，既是终端也是路由器

• 待机模态：仅做中继转发、路由、验签，不主动通讯，低功耗

• 组网模态：主动建群、语音、位置、导航，可面对面建群

• 多跳路由：数据通过多个节点中转，扩展通讯距离

• UID（用户ID）：时间戳+MAC 哈希生成，一机一ID，不可改

• 用户名：用户自定义，组网内不可重复

• 公钥/私钥：身份验证、数据签名、端到端加密

• 积分体系：转发贡献越多积分越高，路由连接优先级越高

• 等高线地图：离线 DEM/瓦片地图，支持坡度、地形、路径导航

• 路径下载：按规划路线自动裁剪下载周边地图包

• 自动寻址：基于地形自动规划最优、最平缓、避障路线
二、整体功能架构

1. 设备身份体系（一机一ID + 用户名）

2. 双模态运行系统（待机 / 组网）

3. 蓝牙 / WiFi 手动/自动通信介质切换

4. Mesh 多跳中继路由网络

5. 端到端非对称加密安全体系

6. 实时语音互传（点对点/群组）

7. 离线等高线地图引擎

8. 路径规划 + 路径式地图下载

9. 自动路径寻址与离线导航

10. 实时 GPS 位置共享与轨迹记录

11. eMULE 风格 P2P 积分激励体系

12. 本地加密存储与数据管理
三、详细功能模块

3.1 用户身份体系（一机一ID）

3.1.1 用户ID（UID）规则

• 生成时机：APP 首次安装启动

• 生成算法：时间戳(毫秒) + 设备MAC加密值 → SHA256哈希 → 唯一UID

• 唯一性：全网唯一，不重复

• 不可更改：除非卸载 APP，否则永久不变

• 存储：Keychain + Secure Enclave 硬件安全区域

• 隐私：网络仅广播哈希 UID，不暴露原始 UID

3.1.2 用户名规则

• 支持汉字、字母、数字、下划线，2–16 位

• 组网内不可重名，可配置为全网唯一

• 可修改，修改需消耗少量积分

• 未设置时默认：萤火用户_XXXX

3.1.3 身份绑定关系

• UID ↔ 积分账户：唯一绑定，不随模态/介质变化

• UID ↔ 公钥/私钥：一一绑定，防伪造

• UID ↔ 设备：一机一ID，不可多机共用同一身份
3.2 双模态运行机制

3.2.1 待机模态（Standby）

• 仅做：数据包验签 → 中继 → 路由转发

• 不主动建群、不语音、不高频定位

• 低功耗：定位 5 分钟/次，关闭 unnecessary 传感器

• 持续累计转发积分

• 自动维护邻居节点与路由表

• 可共享本地离线地图包给组网节点

3.2.2 组网模态（Networking）

• 可发起/加入面对面建群

• 可语音通话、位置共享、路径规划

• 可下载等高线地图、开启导航

• 定位 1 秒/次，地图实时渲染

• 可使用待机节点作为中继远距离通讯

3.2.3 模态切换

• 手动一键切换

• 无操作 15 分钟自动退回待机

• 电量 ≤10% 强制进入待机

• 同一时间仅一种模态生效
3.3 通信介质手动选择

用户可强制指定通信方式：

1. 自动模式（默认）

◦ 语音/位置优先 WiFi

◦ 待机/低电量自动切蓝牙

2. 仅蓝牙

◦ 关闭 WiFi，极低功耗

◦ 适合长时待机、小数据传输

3. 仅 WiFi

◦ 关闭蓝牙，高速大带宽

◦ 适合地图包、群组语音、高密度节点

自动降级机制：

• WiFi 失联 30 秒 → 自动切蓝牙并提示

• 蓝牙干扰严重 → 尝试 WiFi 直连
3.4 Mesh 多跳路由中继

3.4.1 节点发现

• 每 1~3 秒广播心跳包

• 携带：哈希UID、公钥指纹、积分、模态、通信介质

• 自动维护邻居列表与网络拓扑

3.4.2 路由规则

• 支持多跳中继（A→B→C→D…）

• 路径优先级 = 积分权重 + 信号强度 + 跳数 + 介质适配

• 自动选择高积分、高质量链路

• 主链路中断自动切换备用路径

• 数据包带 TTL，防止环路

3.4.3 转发规则

• 仅验签、转发，不解密明文

• 成功送达后反向确认并结算积分

• 地图包优先走 WiFi 中继

• 语音信令可走蓝牙中继
3.5 端到端加密安全体系

3.5.1 密钥体系

• 每设备自动生成 RSA/ECC 公钥+私钥

• 私钥存入 Secure Enclave，不可导出

• 公钥全网公开，用于验签与加密

• 公钥指纹 = 哈希 UID 前 8 位

3.5.2 安全流程

1. 发送方用自己私钥对数据签名

2. 发送方用接收方公钥加密数据

3. 中继节点仅验签，不解密

4. 接收方用发送方公钥验签，用自己私钥解密

5. 群组使用临时会话密钥，群外无法解密

3.5.3 防攻击

• 身份伪造检测：UID + 公钥必须一致

• 恶意节点：积分清零 + 全网拉黑

• 数据包篡改：验签失败直接丢弃
3.6 语音互传功能

• 点对点实时语音

• 群组对讲（一对多、多对多）

• 高清/省电双音质模式

• 锁屏后台可通话

• 语音记录本地加密存储

• 仅组网模态可发起语音
3.7 等高线离线地图

3.7.1 地图能力

• 支持 MBTiles、DEM 高程、等高线矢量

• 离线渲染海拔、坡度、地形纹理

• GCJ-02/WGS84 坐标系自动适配

• 普通地图 / 等高线地图一键切换

3.7.2 路径式地图下载

• 手动绘制起点→途经点→终点

• 支持导入 GPX/KML 轨迹

• 可设置路径缓冲：500m/1km/2km/5km

• 自动裁剪仅下载路径区域地图包

• 断点续传、分批次下载

• 地图包加密签名，防篡改

3.7.3 自动路径寻址

• 基于地形分析坡度、陡坡、水域、障碍

• 提供 1~3 条路线：最优/最短/最平缓

• 偏离路线自动重新规划

• 危险地形高亮预警

• 支持标记水源、营地、危险点、集合点

3.7.4 离线导航

• 实时方向 + 距离 + 坡度提示

• 语音+文字双重提醒

• 轨迹记录与 GPX 导出

• 无外网完全可用
3.8 实时位置共享

• 组网节点 1 秒/次上传位置

• 待机节点 5 分钟/次粗略位置

• 地图显示自身、群成员、中继节点

• 实时测距、方位、指南针

• 移动轨迹记录与回放

• 位置数据加密传输
3.9 积分激励体系（eMULE 风格）

3.9.1 积分获取

• 基础数据转发：+1/次

• WiFi 中继转发：+2/次

• 唯一关键中继：+3/次

• 待机稳定在线：+5/5分钟（日上限100）

• 地图包转发共享：+1/次

• 有效路径规划导航：+5/次

3.9.2 积分消耗

• 语音通话：-2/10分钟

• 位置共享：-1/10分钟

• 面对面建群：-50/次

• 大地图包下载：-5/次

• 导航重规划：-2/次

3.9.3 衰减与惩罚

• 7 天无操作：积分衰减 20%

• 15 天无操作：衰减 50%

• 离线 ≥24 小时：积分清零

• 恶意发包/伪造身份：积分清零+拉黑

3.9.4 积分优先级

• 黄金节点：>200 最高优先级

• 白银节点：100~200 中优先级

• 青铜节点：<100 低优先级
积分越高越容易被选为中继，连接更快更稳。
四、iOS 实现可行性结论

全部功能均可在 iPhone / iOS 原生实现，无不可逾越限制。

可实现部分：

• 蓝牙 / WiFi P2P 通信（CoreBluetooth / Network.framework）

• 多跳 Mesh 中继与路由表

• 公钥私钥加密与 Secure Enclave 存储

• 一机一ID 与 Keychain 持久化

• 离线等高线地图与 DEM 渲染

• 路径规划与 A* 避障导航

• 后台低功耗待机中继

• 积分本地记账与 Mesh 同步

约束与注意：

• 后台扫描会被系统节流，需配合定位后台模式

• 地图包较大时需做内存分页加载

• 审核需清晰说明权限用途（蓝牙/定位/本地网络）

• 必须真机调试，模拟器无法完整测试 Mesh
五、本地研发环境（硬件 + 软件 + 环境）

5.1 硬件要求

开发主机（必选）

• 机型：MacBook Pro / Mac mini（M2/M3/M4 系列）

• 系统：macOS Sonoma 14.5+

• 内存：≥32GB（强烈建议）

• 存储：≥1TB SSD

• 网络：WiFi 6/蓝牙 5.0 以上

测试真机（必选，最少 2 台，推荐 3 台）

• iPhone 13 / 14 / 15 / 16 系列

• iOS 15.0 以上

• 支持 GPS、蓝牙 5.0+、WiFi Direct

• 用于测试：Mesh 中继、多跳、语音、地图、位置

辅助硬件

• USB-C to Lightning 数据线

• 便携路由器/热点（可选）

5.2 软件与开发工具

• Xcode 15.4+（主 IDE）

• Apple 开发者账号（99 美元/年，真机调试必备）

• Homebrew（包管理）

• Git（代码版本管理）

• OpenSSL（加密）

• SQLite（地图与本地存储）

• Mapbox iOS SDK / 离线地图渲染引擎

• GDAL（地形与高程解析）

5.3 Xcode 能力开启

• Background Modes

◦ Uses Bluetooth LE accessories

◦ Acts as a Bluetooth LE server

• Local Network 权限

• 定位始终允许

• 麦克风权限

• 钥匙串访问权限

5.4 开发工作流

1. 本地 Mac 编写代码

2. 连接 iPhone 真机调试

3. 测试多设备 Mesh 中继

4. 测试等高线地图与导航

5. 测试蓝牙/WiFi 切换

6. TestFlight 内部分发测试
六、研发版本规划

V1.0（MVP）

• 一机一ID + 用户名

• 待机/组网双模态

• 蓝牙/WiFi 基础连接

• 简单多跳中继

• 公钥私钥验签加密

• 基础点对点语音

• 基础离线地图

V2.0

• 面对面建群

• 群组语音

• 积分体系完整上线

• 等高线地图渲染

• 路径规划与路径下载

V3.0

• 自动路径寻址与导航

• 多跳稳定路由

• 地图包中继共享

• 完整积分优先级调度

• 低功耗后台优化
七、版权与说明

本文档为《夏日萤火》APP 完整产品研发规格，
包含所有功能细节、架构、安全、积分、地图、研发环境，
可直接作为产品需求文档（PRD）+ 研发说明书使用。

---

# 附录：功能修复与优化记录

## A1. PTT语音功能修复（260601）

### A1.1 问题描述

**用户原始需求**：按下PTT按钮后，录制的语音应该发往**群组**，而不是个人。

**代码分析发现的问题**：
- `VoiceService.handleInputBuffer()` 第627行要求 `currentCall` 必须存在
- 如果 `currentCall` 为 nil，音频数据直接被丢弃
- PTT在无active call时完全不工作

### A1.2 修复内容

#### 1. VoiceService.swift 核心修复

| 修改项 | 说明 |
|--------|------|
| 新增 `isPTTMode: Bool` | 追踪PTT是否正在传输 |
| 新增 `currentGroupId: String?` | 存储当前群组上下文 |
| 新增 `currentGroupName: String?` | 存储当前群组名称（用于UI显示） |
| 新增 `joinGroupCall(groupId:)` | 当PTT无call时自动创建群组通话 |
| 新增 `setCurrentGroup(_:name:)` | 供UI设置当前群组上下文 |
| 修改 `handleInputBuffer()` | 允许PTT mode下音频通过（修复数据竞争） |
| 修改 `startTransmitting()` | 无active call时自动加入群组 |
| 修改 `endGroupCall()` | 清理 currentGroupId |

#### 2. ContentView.swift / UIComponentViews.swift 修复

| 修改项 | 说明 |
|--------|------|
| GroupsListView 点击调用 `setCurrentGroup()` | UI与Service连接 |
| PTT按钮显示 `currentGroupName` | 用户可见当前群组 |
| PTTErrorHandler 单例 | 处理 `didFailWithError` 回调 |
| Alert 弹窗提示"请先选择一个群组再使用PTT" | 友好错误提示 |

#### 3. Localizable.strings 中英文支持

```
ptt_no_group = "未选择群组";
ptt_error_no_group = "请先选择一个群组再使用PTT";
ptt_error_title = "PTT错误";
select_group = "选择群组";
```

### A1.3 代码审计问题与修复

| 优先级 | 问题 | 修复方案 | 状态 |
|--------|------|----------|------|
| P0 | handleInputBuffer()数据竞争 | 音频线程捕获状态副本 | ✅ 已修复 |
| P1 | 每个音频包dispatch性能问题 | 编码/加密在音频线程完成 | ✅ 已修复 |
| P2 | endGroupCall()未清理currentGroupId | 增加 nil 清理 | ✅ 已修复 |
| P2 | startTransmitting()递归调用风险 | DispatchQueue.main.async包裹 | ✅ 已修复 |
| P3 | 引用循环 | [weak self]明确 | ✅ 已修复 |

### A1.4 用户体验问题与修复

| 问题 | 修复方案 | 状态 |
|------|----------|------|
| UI与Service脱节 | GroupsListView点击调用setCurrentGroup | ✅ 已修复 |
| 静默失败 | startTransmitting()无群组时发didFailWithError | ✅ 已修复 |
| 错误处理缺失 | 新增PTTErrorHandler单例 | ✅ 已修复 |
| 群组不可见 | PTT按钮显示currentGroupName | ✅ 已修复 |

### A1.5 视觉设计问题（待修复）

| 问题 | 建议修复方案 | 状态 |
|------|-------------|------|
| 状态颜色混淆 | 灰色默认态与iOS禁用态语义重叠，需重新设计颜色语义 | ❌ 待修复 |
| 文字可读性差 | 群组名称10pt+80%透明度，需增加字号或对比度 | ❌ 待修复 |
| API过时 | 使用已废弃NavigationView，建议迁移到NavigationStack | ❌ 待修复 |
| 错误提示不友好 | 直接显示技术性error.localizedDescription，建议使用友好本地化字符串 | ❌ 待修复 |

### A1.6 PTT功能流程图

```
用户按压PTT按钮
    ↓
VoiceService.startTransmitting()
    ↓
检查 currentCall 是否存在
    ↓ 是 → 正常传输音频到群组
    ↓ 否 → 检查 currentGroupId
              ↓ 存在 → 自动joinGroupCall() → 传输
              ↓ 不存在 → 触发 didFailWithError → UI显示Alert
```

### A1.7 验证结果

| 阶段 | 判定 | 说明 |
|------|------|------|
| 代码审计（初） | FAIL | P0数据竞争等问题 |
| 代码审计（复） | PASS | 所有问题已修复 |
| 用户体验（初） | FAIL | UI与Service脱节等 |
| 用户体验（复） | PASS | 所有问题已修复 |
| 视觉设计 | FAIL | 颜色/字号/API等问题待修复 |
| 编译验证 | PASS | BUILD SUCCEEDED |

### A1.8 相关文件清单

| 文件 | 修改类型 |
|------|---------|
| src/Modules/Voice/VoiceService.swift | 修改 |
| src/App/ContentView.swift | 修改 |
| src/App/UIComponentViews.swift | 修改 |
| src/Modules/Voice/VoiceCallManager.swift | 修改 |
| src/Resources/en.lproj/Localizable.strings | 追加 |
| src/Resources/zh-Hans.lproj/Localizable.strings | 追加 |

---

# 附录：功能修复与优化记录

## A1. PTT语音功能修复（260601）

### A1.1 问题描述

**用户原始需求**：按下PTT按钮后，录制的语音应该发往**群组**，而不是个人。

**代码分析发现的问题**：
- `VoiceService.handleInputBuffer()` 第627行要求 `currentCall` 必须存在
- 如果 `currentCall` 为 nil，音频数据直接被丢弃
- PTT在无active call时完全不工作

### A1.2 修复内容

#### 1. VoiceService.swift 核心修复

| 修改项 | 说明 |
|--------|------|
| 新增 `isPTTMode: Bool` | 追踪PTT是否正在传输 |
| 新增 `currentGroupId: String?` | 存储当前群组上下文 |
| 新增 `currentGroupName: String?` | 存储当前群组名称（用于UI显示） |
| 新增 `joinGroupCall(groupId:)` | 当PTT无call时自动创建群组通话 |
| 新增 `setCurrentGroup(_:name:)` | 供UI设置当前群组上下文 |
| 修改 `handleInputBuffer()` | 允许PTT mode下音频通过（修复数据竞争） |
| 修改 `startTransmitting()` | 无active call时自动加入群组 |
| 修改 `endGroupCall()` | 清理 currentGroupId |

#### 2. ContentView.swift / UIComponentViews.swift 修复

| 修改项 | 说明 |
|--------|------|
| GroupsListView 点击调用 `setCurrentGroup()` | UI与Service连接 |
| PTT按钮显示 `currentGroupName` | 用户可见当前群组 |
| PTTErrorHandler 单例 | 处理 `didFailWithError` 回调 |
| Alert 弹窗提示"请先选择一个群组再使用PTT" | 友好错误提示 |

#### 3. Localizable.strings 中英文支持

```
ptt_no_group = "未选择群组";
ptt_error_no_group = "请先选择一个群组再使用PTT";
ptt_error_title = "PTT错误";
select_group = "选择群组";
```

### A1.3 代码审计问题与修复

| 优先级 | 问题 | 修复方案 | 状态 |
|--------|------|----------|------|
| P0 | handleInputBuffer()数据竞争 | 音频线程捕获状态副本 | ✅ 已修复 |
| P1 | 每个音频包dispatch性能问题 | 编码/加密在音频线程完成 | ✅ 已修复 |
| P2 | endGroupCall()未清理currentGroupId | 增加 nil 清理 | ✅ 已修复 |
| P2 | startTransmitting()递归调用风险 | DispatchQueue.main.async包裹 | ✅ 已修复 |
| P3 | 引用循环 | [weak self]明确 | ✅ 已修复 |

### A1.4 用户体验问题与修复

| 问题 | 修复方案 | 状态 |
|------|----------|------|
| UI与Service脱节 | GroupsListView点击调用setCurrentGroup | ✅ 已修复 |
| 静默失败 | startTransmitting()无群组时发didFailWithError | ✅ 已修复 |
| 错误处理缺失 | 新增PTTErrorHandler单例 | ✅ 已修复 |
| 群组不可见 | PTT按钮显示currentGroupName | ✅ 已修复 |

### A1.5 视觉设计问题与修复

| 问题 | 修复方案 | 状态 |
|------|-------------|------|
| 状态颜色混淆 | pttButtonColor计算属性，区分4种语义状态 | ✅ 已修复 |
| 文字可读性差 | 群组名称字号改为14pt，100%透明度 | ✅ 已修复 |
| API过时 | 9个NavigationView迁移NavigationStack | ✅ 已修复 |
| 错误提示不友好 | mapToFriendlyErrorMessage()本地化字符串 | ✅ 已修复 |

### A1.6 PTT功能流程图

```
用户按压PTT按钮
    ↓
VoiceService.startTransmitting()
    ↓
检查 currentCall 是否存在
    ↓ 是 → 正常传输音频到群组
    ↓ 否 → 检查 currentGroupId
              ↓ 存在 → 自动joinGroupCall() → 传输
              ↓ 不存在 → 触发 didFailWithError → UI显示Alert
```

### A1.7 验证结果

| 阶段 | 判定 | 说明 |
|------|------|------|
| 代码审计（初） | FAIL | P0数据竞争等问题 |
| 代码审计（复） | PASS | 所有问题已修复 |
| 用户体验（初） | FAIL | UI与Service脱节等 |
| 用户体验（复） | PASS | 所有问题已修复 |
| 视觉设计（初） | FAIL | 颜色/字号/API等问题 |
| 视觉设计（复） | PASS | 所有问题已修复 |
| 编译验证 | PASS | BUILD SUCCEEDED |

### A1.8 相关文件清单

| 文件 | 修改类型 |
|------|---------|
| src/Modules/Voice/VoiceService.swift | 修改 |
| src/App/ContentView.swift | 修改 |
| src/App/UIComponentViews.swift | 修改 |
| src/Modules/Voice/VoiceCallManager.swift | 修改 |
| src/Resources/en.lproj/Localizable.strings | 追加 |
| src/Resources/zh-Hans.lproj/Localizable.strings | 追加 |

### A1.9 详细报告索引

| 报告 | 路径 |
|------|------|
| 主日志 | ~/Documents/summer-spark/main-log.md |
| 审计报告（初） | ~/Documents/summer-spark/ptt-audit-report.md |
| 审计报告（复） | ~/Documents/summer-spark/ptt-re-audit-report.md |
| 用户体验报告（初） | ~/Documents/summer-spark/ptt-ux-report.md |
| 用户体验报告（复） | ~/Documents/summer-spark/ptt-ux-re验证-report.md |
| 视觉设计报告 | ~/Documents/summer-spark/ptt-visual-report.md |
| 视觉设计复验 | ~/Documents/summer-spark/ptt-visual-re验证-report.md |

---

## A2. UI功能修复（260601 第二轮）

### A2.1 问题描述

**用户反馈问题**：
1. 点击群组 → 创建群组，没有任何反应
2. 离线地图只能下载浙江省/杭州市/西湖区，无法自定义下载
3. 添加通讯录 → 扫码，没有反应
4. 用户名修改后，在用户设置页面仍显示"User"

**用户体验专家深度分析发现的问题**：
| 问题 | 状态 | 严重程度 | 根因 |
|------|------|----------|------|
| 问题1: 创建群组无反应 | FAIL | HIGH | GroupsListView第112行只有TODO注释 |
| 问题2: 离线地图无法自定义 | FAIL | MEDIUM | 区域硬编码数组 |
| 问题3: 扫码无反应 | FAIL | HIGH | showScanner未绑定sheet |
| 问题4: 用户名不刷新 | FAIL | MEDIUM | username非@Published |
| 额外C: 双重NavigationStack | FAIL | LOW | - |
| 额外D: ProfileView NavigationView | FAIL | MEDIUM | 使用废弃API |
| 额外E: QuickActionsSection硬编码 | FAIL | LOW | 按钮顺序硬编码 |

### A2.2 修复内容

#### 问题1: 创建群组无反应

| 项目 | 内容 |
|------|------|
| 文件 | UIComponentViews.swift |
| 修复 | 添加showCreateGroupAlert和newGroupName状态，实现创建群组Alert和createGroup()方法 |
| 验证 | ✅ PASS |

#### 问题2: 离线地图无法自定义

| 项目 | 内容 |
|------|------|
| 文件 | UIComponentViews.swift, OfflineMapManager.swift |
| 修复 | OfflineMapManager添加getAvailableRegions()动态获取区域，UIComponentViews.swift移除硬编码 |
| 验证 | ✅ PASS |

#### 问题3: 扫码无反应

| 项目 | 内容 |
|------|------|
| 文件 | UIComponentViews.swift |
| 修复 | 添加sheet(isPresented: $showScanner)绑定，实现ScannerView和QRScannerViewController |
| 验证 | ✅ PASS |

#### 问题4: 用户名修改后UI不刷新

| 项目 | 内容 |
|------|------|
| 文件 | IdentityManager.swift, ContentView.swift, UIComponentViews.swift |
| 修复 | IdentityManager.username改为@Published，ProfileView/AccountSettingsView使用@ObservedObject |
| 验证 | ✅ PASS |

#### 额外问题C: 双重NavigationStack

| 项目 | 内容 |
|------|------|
| 验证 | ✅ PASS - 不存在双重嵌套问题 |

#### 额外问题D: ProfileView NavigationView

| 项目 | 内容 |
|------|------|
| 文件 | ContentView.swift |
| 修复 | ProfileView从NavigationView迁移到NavigationStack |
| 验证 | ✅ PASS |

#### 额外问题E: QuickActionsSection硬编码

| 项目 | 内容 |
|------|------|
| 文件 | RescueDashboard.swift, ContentView.swift |
| 修复 | 新增QuickActionConfig模型和QuickActionsConfiguration，QuickActionsSection改为数据驱动 |
| 验证 | ✅ PASS |

### A2.3 语法错误修复

| 错误 | 修复 |
|------|------|
| UIComponentViews.swift:613 多余`}` | 移动addContactByID()方法到正确位置 |
| OfflineMapInfo未遵循Identifiable | 添加Identifiable协议到MapService.swift |

### A2.4 验证结果

| 问题 | 判定 |
|------|------|
| 问题1: 创建群组 | ✅ PASS |
| 问题2: 离线地图 | ✅ PASS |
| 问题3: 扫码 | ✅ PASS |
| 问题4: 用户名刷新 | ✅ PASS |
| 额外C: 双重NavigationStack | ✅ PASS |
| 额外D: NavigationView迁移 | ✅ PASS |
| 额外E: QuickActionsSection | ✅ PASS |
| 编译验证 | ✅ BUILD SUCCEEDED |

### A2.5 相关文件清单

| 文件 | 修改类型 |
|------|---------|
| src/App/UIComponentViews.swift | 修改 |
| src/App/ContentView.swift | 修改 |
| src/Modules/Identity/IdentityManager.swift | 修改 |
| src/Modules/Map/OfflineMapManager.swift | 修改 |
| src/Modules/Map/MapService.swift | 修改 |
| src/Modules/UI/RescueDashboard.swift | 修改 |
| src/Resources/en.lproj/Localizable.strings | 修改 |
| src/Resources/zh-Hans.lproj/Localizable.strings | 修改 |

### A2.6 详细报告索引

| 报告 | 路径 |
|------|------|
| 主日志 | ~/Documents/summer-spark/main-log.md |
| UX分析报告 | ~/Documents/summer-spark/round2-ux-analysis.md |
| UX验证报告 | ~/Documents/summer-spark/round2-ux-verification.md |
| UX最终验证 | ~/Documents/summer-spark/round2-final-verification.md |

---

### A3. 面对面建群功能修复记录

#### A3.1 问题描述

| # | 严重度 | 问题 | 来源 |
|---|--------|------|------|
| 1 | 严重 | GroupStore.addMember()权限检查导致新建群组后owner无法添加第一个成员 | UX第一轮验证 |
| 2 | 严重 | 数字码加入功能为桩代码，未实现 | UX第一轮验证 |
| 3 | 中等 | 缺少实时倒计时UI（只显示过期时间点） | UX第一轮验证 |
| 4 | 设计缺陷 | 6位数字码用hashValue取模，不可逆，无法从数字码反推groupId | UX第一轮验证 |
| 5 | 审计FAIL | addMember权限检查与面对面建群流程冲突，joiner无法通过权限检查 | 代码审计第一轮 |
| 6 | 审计FAIL | 数字码加入缺少过期校验（安全漏洞） | 代码审计第一轮 |
| 7 | 审计FAIL | Base36解码使用UTF-8，字节非合法UTF-8时返回nil | 代码审计第一轮 |

#### A3.2 修复记录

| 日期 | 修复内容 | 工程师 |
|------|---------|--------|
| 260601 1455 | FaceToFaceGroupView集成，移除扣积分逻辑 | iOS研发专家 |
| 260601 1545 | 修复问题1-4：GroupStore.createGroup重复owner、数字码加入实现、倒计时UI、Base36编码 | iOS研发专家 |
| 260601 1610 | 修复审计FAIL项：确认Group.init已初始化members为空数组、添加过期校验、改用Latin1编码 | iOS研发专家 |
| 260601 1645 | 修复addMember权限冲突：新增addMemberWithoutPermission()方法 | iOS研发专家 |

#### A3.3 验收记录

| 日期 | 验收项 | 结果 |
|------|--------|------|
| 260601 1500 | UX第一轮验证 | FAIL（发现4个问题） |
| 260601 1610 | 代码审计第一轮 | FAIL（3项FAIL） |
| 260601 1630 | iOS研发修复后xcodebuild | BUILD SUCCEEDED |
| 260601 1700 | UX第二轮验证 | FAIL（addMember权限冲突） |
| 260601 1708 | 代码审计第二轮 | PASS |
| 260601 1708 | 美工视觉验收 | PASS |
| 260601 1710 | UX第三轮验证 | PASS |

#### A3.4 最终验收结论

| 角色 | 结论 |
|------|------|
| UX专家 | ✅ PASS（三轮验证） |
| 代码审计 | ✅ PASS（两轮复核） |
| 美工 | ✅ PASS |

#### A3.5 相关文件清单

| 文件 | 修改类型 |
|------|---------|
| src/Modules/Social/FaceToFaceModels.swift | 新建+修改 |
| src/Modules/Social/FaceToFaceGroupManager.swift | 新建+修改 |
| src/Modules/Social/FaceToFaceGroupView.swift | 新建+修改 |
| src/Modules/Storage/GroupStore.swift | 修改 |
| src/App/UIComponentViews.swift | 修改 |
| src/App/ContentView.swift | 修改 |
| SummerSpark.xcodeproj/project.pbxproj | 修改 |

---

**最后更新**: 260601 1710


