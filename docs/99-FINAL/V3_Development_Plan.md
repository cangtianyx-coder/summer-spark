# V3.0 开发计划 — 夏日萤火 / SummerSpark

## 目标
完成 V3.0 的 5 个关键增强模块，从 MVP 迈向生产可用。

## 现状盘点

| 模块 | V1.0 状态 | V3.0 目标 | 差距 |
|------|-----------|-----------|------|
| 路径寻址与导航 | PathPlanner A* 基础实现 | 地理位置寻址 + Geocast | 需增强寻址协议 |
| 稳定多跳路由 | MeshService 基础路由 | QoS感知 + 链路质量评分 + 自动切换 | 需路由稳定性增强 |
| 地图包中继共享 | OfflineMapManager 单节点下载 | P2P地图包中继共享 | 需 Mesh 中继能力 |
| 积分优先级调度 | CreditEngine stub | 完整积分优先级调度队列 | 需调度引擎实现 |
| 低功耗后台 | 无后台优化 | BLE后台监听 + 自适应信标 | 需功耗管理模块 |

---

## V3.0 架构

### 新增文件清单

#### 1. 路径寻址与导航增强 (`src/Modules/Navigation/`)
- `GeoAddressing.swift` — 地理位置寻址（Geocast）协议
- `GeoMeshNavigator.swift` — 基于 Mesh 的地理导航引擎

#### 2. 稳定多跳路由增强 (`src/Modules/Mesh/`)
- `RouteStabilityMonitor.swift` — 链路质量监控与路由评分
- `QoSRouter.swift` — QoS 感知路由选择器
- `RouteHandoverManager.swift` — 路由切换与故障转移

#### 3. 地图包中继共享 (`src/Modules/MapRelay/`)
- `MapRelayService.swift` — 地图包 Mesh 中继服务
- `MapPackageP2P.swift` — P2P 地图包分发协议
- `TileIntegrityVerifier.swift` — 瓦片完整性校验

#### 4. 积分优先级调度 (`src/Modules/Scheduler/`)
- `PriorityScheduler.swift` — 积分优先级消息调度器
- `CreditQoSController.swift` — 积分 QoS 控制器
- `ReputationTracker.swift` — 节点信誉追踪

#### 5. 低功耗后台优化 (`src/Modules/Power/`)
- `PowerSaveManager.swift` — 功耗状态机管理
- `BackgroundMeshListener.swift` — BLE 后台 Mesh 监听
- `AdaptiveBeaconController.swift` — 自适应信标控制器

#### 6. Shared 层增强 (`src/Shared/`)
- `Models/GeoModels.swift` — 地理位置数据模型
- `Models/QoSModels.swift` — QoS 相关数据模型
- `Protocols/MeshRelayProtocols.swift` — 中继服务协议

#### 7. 文档
- `docs/03-NAV/V3_GeoAddressing_Spec.md`
- `docs/03-MESH/V3_RouteStability_Spec.md`
- `docs/06-MAP/V3_MapRelay_Spec.md`
- `docs/07-PTS/V3_CreditScheduler_Spec.md`
- `docs/08-POWER/V3_PowerSave_Spec.md`
- `docs/99-FINAL/FINAL_Changelog.md`（更新）

---

## 开发顺序

1. **Shared 层增强**（GeoModels, QoSModels, MeshRelayProtocols）— 所有模块依赖
2. **并行批次 1**（3 agents）
   - Navigation Agent: GeoAddressing + GeoMeshNavigator
   - Mesh Agent: RouteStabilityMonitor + QoSRouter + RouteHandoverManager
   - Credit Agent: PriorityScheduler + CreditQoSController + ReputationTracker
3. **并行批次 2**（2 agents）
   - MapRelay Agent: MapRelayService + MapPackageP2P + TileIntegrityVerifier
   - Power Agent: PowerSaveManager + BackgroundMeshListener + AdaptiveBeaconController
4. **集成测试**：编译验证 + 依赖检查
5. **文档更新**：更新 Changelog + 项目摘要

---

## 验收标准

- [ ] 编译通过，0 错误
- [ ] 所有新增协议有实现，所有 stub 方法有填充
- [ ] 低功耗模块正确处理后台状态切换
- [ ] 积分调度优先级逻辑正确
- [ ] 地图中继支持多跳传播
- [ ] 路由切换在链路质量下降时自动触发
