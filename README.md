# 🎓 HNU Course Selector | 海大抢课助手

基于 Selenium 的抢课辅助工具，集成了验证码自动识别、预选课表解析、自动启动抢课等功能。

![Python](https://img.shields.io/badge/Python-3.13+-blue.svg)
![Selenium](https://img.shields.io/badge/Selenium-4.0+-green.svg)
[![Framework](https://img.shields.io/badge/UI-CustomTkinter-0371F1)](https://github.com/TomSchimansky/CustomTkinter)
[![OCR](https://img.shields.io/badge/OCR-ddddocr-orange)](https://github.com/sml2h3/ddddocr)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

---

## ⚠️ 免责声明

**在使用本项目之前，请务必阅读以下内容：**

1.  **用途限制**：本项目仅供 **Python 自动化技术研究** 与 **网络协议分析学习** 使用。请勿将其用于任何违反学校教务规章制度的行为。
2.  **风险自担**：本项目的作者（以下简称“作者”）不对代码的完整性、可靠性及准确性做任何保证。在任何情况下，由于使用本项目所产生的任何直接、间接、偶然、特殊的损害或后果（包括但不限于选课失败、账号被封禁、学分损失或被校方处分），作者均不承担任何法律责任。
3.  **公平竞争**：使用者在下载、运行本项目代码前，应自行了解并遵守所属学校教务系统的《用户协议》、《选课规范》及相关的计算机使用准则。作者不鼓励、不支持、不参与任何破坏教育公平、干扰校园网络正常运行的行为。请合理使用技术手段，共同维护校园选课系统的公平与稳定。
4.  **最终解释权**：使用者一旦开始使用本项目代码，即视为已阅读并完全接受本声明的所有条款。作者保留随时修改此声明的权利。

---

## 🛠️ 环境要求

-   Python 3.13+
-   Edge 浏览器
-   对应版本的 [EdgeDriver](https://developer.microsoft.com/en-us/microsoft-edge/tools/webdriver/)

---

## 🚀 快速开始

### 1. 环境准备
确保您的电脑已安装 Python 3.13 或更高版本。

```bash
# 克隆仓库或下载源代码
git clone https://github.com/SakuraXi/HNUCourseSelector.git
# 安装依赖库
pip install requests selenium customtkinter ddddocr Pillow
```

### 2. 浏览器驱动
本项目默认使用 **Microsoft Edge** 浏览器。请确保您的电脑已安装 Edge，并下载对应版本的 [msedgedriver](https://developer.microsoft.com/en-us/microsoft-edge/tools/webdriver/) 放入系统环境变量或项目根目录。

### 3. 运行程序
```bash
python GUI.py
```

---

## 📖 使用步骤

1.  **导入课程**：
    *   登录教务系统的【学生选课】页面，并进入本次选课的【预选轮次】
    *   点击【选课结果】按钮，会弹出一个单独的选课结果窗口。
    *   在此窗口【右键】 -> 【另存为】（或按键盘Ctrl + S组合键） -> 选择【仅 HTML】
    *   在助手的“预选列表”页面点击 **📂 导入预选课程**
    *   在列表中勾选你想要抢的课程
2.  **参数设置**：
    *   在“配置设置”页面输入学号和密码。
    *   如需定时启动，开启“自动抢课”开关并设定时间（格式：`yyyy-MM-dd HH:mm:ss`）。
3.  **开始执行**：
    *   回到“控制主页”，设置尝试轮数（推荐 5-10 轮）和轮次延迟。
    *   点击 **开始抢课**，程序将自动接管操作并在日志框实时反馈结果。

---

## 📁 文件结构

*   `GUI.py`: 程序主入口，负责 UI 渲染与交互逻辑。
*   `MainService.py`: 核心业务逻辑，包含浏览器自动化、登录及抢课请求。
*   `getInfos.py`: 课程解析模块，负责从 HTML 文件中提取课程数据。
*   `Utils.py`: 工具类，提供单例模式的请求会话管理（SessionMgr）。
*   `config.json`: 用户配置文件，存储账号、密码、启动时间等。
*   `parsedCourses.json`: 解析后的预选课程数据。
* 
---

## ❤️ 感谢使用
用着还不错的话给我点个Star⭐呗（求你了）
---
