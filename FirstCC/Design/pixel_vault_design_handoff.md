# PIXEL_VAULT 前端交付文档 (Design Handoff - 中文版)

这份文档包含了 **PIXEL_VAULT** 应用的核心设计令牌、组件规范及中文字体本地化指南。该设计融合了 iOS 26 “液态玻璃”美学与 8-bit 像素艺术元素。

## 1. 字体规范 (Typography)

为了在保持像素风的同时确保中文的可读性，我们采用了双字体系统：
- **英文字体/数字**：`Space Grotesk` (保持品牌的高级极客感)
- **中文字体**：`PingFang SC` (苹果系统默认字体，确保在玻璃材质下的清晰度)

```css
/* 字体定义示例 */
body {
    font-family: 'Space Grotesk', 'PingFang SC', sans-serif;
}
```

## 2. 设计令牌 (Tailwind CSS)

### 浅色模式 (Luminous Glass)
```javascript
"colors": {
    "surface": "#fcf9f8",
    "primary": "#006d35",
    "primary-container": "#00d16b",
    "on-surface": "#1c1b1b",
    "on-surface-variant": "#3c4a3d",
    "surface-container": "#f0edec",
    "glass-bg": "rgba(255, 255, 255, 0.4)",
    "glass-border": "rgba(255, 255, 255, 0.3)"
}
```

### 深色模式 (Pixel-Glass)
```javascript
"colors": {
    "surface": "#131313",
    "primary": "#00ff7f",
    "on-surface": "#ffffff",
    "surface-container": "#1c1b1b",
    "glass-bg": "rgba(255, 255, 255, 0.05)",
    "glass-border": "rgba(255, 255, 255, 0.1)"
}
```

## 3. 核心 UI 组件

### 液态玻璃卡片 (Glassmorphism)
```css
.glass-card {
    backdrop-filter: blur(20px);
    background: var(--glass-bg);
    border: 1px solid var(--glass-border);
    box-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.1);
    border-radius: 2rem; /* 匹配 iOS 大圆角 */
}
```

### 像素边框 (Pixel Art Border)
用于图标容器或按钮，增强复古味：
```css
.pixel-border {
    box-shadow: 
        0 -2px 0 0 currentColor,
        0 2px 0 0 currentColor,
        -2px 0 0 0 currentColor,
        2px 0 0 0 currentColor;
}
```

## 4. 中文版效果图索引
- **首页总览 (深色)**: {{DATA:SCREEN:SCREEN_59}}
- **账目列表 (浅色)**: {{DATA:SCREEN:SCREEN_57}}
- **记账页面 (深色)**: {{DATA:SCREEN:SCREEN_108}}
- **统计报表 (浅色)**: {{DATA:SCREEN:SCREEN_110}}

## 5. 本地化词条对照
- Vault -> 小金库
- Flow -> 流水
- Goals -> 目标
- Profile -> 我的
- Log Transaction -> 记录这笔账单
- Efficiency Score -> 财务健康分
