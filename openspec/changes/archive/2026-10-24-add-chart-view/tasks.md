# Tasks

## 1. 数据层

- [x] 1.1 定义 ChartSpec、ChartKind、ChartData，验证四种类型与数值解析
- [x] 1.2 ChartData 取前 12 加“其他”，验证 900 组收口后 13 个点
- [x] 1.3 图表复用 pivot 查询，验证区域求和的数值与手写 GROUP BY 一致

## 2. 状态层

- [x] 2.1 WorkspaceModel 增加 runChart 与图表状态，验证跟随当前视图
- [x] 2.2 0 行时给出提示，验证不画空图（ChartData 空结果测试通过）

## 3. 界面

- [x] 3.1 工具栏加“图表”按钮与配置面板，验证分组列与度量列可切换
- [x] 3.2 Canvas 画柱状图与条形图，验证最多 13 个柱
- [x] 3.3 Canvas 画折线图与饼图，验证切换不崩
- [x] 3.4 结果区显示标题、耗时与“返回数据”，验证能回到表格

## 4. 验证

- [x] 4.1 测试程序覆盖数值解析、前 12 收口、空数据
- [x] 4.2 开发包里用 328 万行文件过一遍四种图
- [x] 4.3 运行 openspec validate --strict add-chart-view
