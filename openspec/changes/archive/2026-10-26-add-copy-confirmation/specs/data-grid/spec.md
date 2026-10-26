# Specification Delta

## ADDED Requirements

### Requirement: 大选区复制前确认

系统 SHALL 在复制选区超过 10000 行时先弹确认框，取消时不修改剪贴板。

#### Scenario: 选中两万行复制

- **WHEN** 用户选中 20000 行按 Command+C
- **THEN** 弹出确认框说明行数，点取消后剪贴板内容不变
