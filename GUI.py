# -*- coding: utf-8 -*-
# @Time    : 2026-07-21
# @Author  : xlxlSakura
# @FileName: GUI.py
# @Software: PyCharm
# @Description: 抢课助手UI页面
# @Version: 1.0

import json
import os
import queue
import threading
import sys

import re
from datetime import datetime
import customtkinter as ctk
from tkinter import messagebox, filedialog

import MainService
import getInfos

ctk.set_appearance_mode("Light")
ctk.set_default_color_theme("blue")

THEME_BLUE = "#0371F1"
BG_WHITE = "#FFFFFF"
CARD_BG = "#F8F9FA"


class Logger:
    """日志重定向工具，用于将 stdout 输出到 UI 文本框"""
    def __init__(self, textbox: ctk.CTkTextbox):
        self.textbox = textbox
        self.msg_queue = queue.Queue()
        # 启动定时检查队列的任务
        self.update_loop()

    def write(self, message):
        # 过滤掉只有换行符的无意义消息
        if message and message.strip():
            now = datetime.now().strftime("%H:%M:%S")
            # 处理多行消息，确保每行都有时间戳
            lines = message.strip().split('\n')
            for line in lines:
                formatted_msg = f"[{now}] {line}\n"
                self.msg_queue.put(formatted_msg)

    def flush(self):
        pass

    def update_loop(self):
        """定期从队列中提取消息并更新 UI"""
        try:
            while True:
                # 尝试获取所有排队的消息
                msg = self.msg_queue.get_nowait()
                self.textbox.configure(state="normal")
                self.textbox.insert("end", msg)
                self.textbox.see("end")
                self.textbox.configure(state="disabled")
        except queue.Empty:
            pass
        finally:
            # 每 100ms 检查一次队列
            self.textbox.after(100, self.update_loop)


class CourseCard(ctk.CTkFrame):
    """课程卡片组件"""

    def __init__(self, master, info: dict, on_toggle, **kwargs):
        super().__init__(master, fg_color=CARD_BG, corner_radius=10, **kwargs)
        self.info = info

        # 布局
        self.grid_columnconfigure(1, weight=1)

        # 状态标签 (演示用)
        status_color = "#2ECC71" if info.get("status") == "已选" else "#95A5A6"
        self.status_indicator = ctk.CTkLabel(self, text=" ● ", text_color=status_color, width=10)
        self.status_indicator.grid(row=0, column=0, padx=(10, 0), pady=10)

        # 课程信息
        title_text = f"{info['courseName']} ({info['courseNum']})"
        self.title_label = ctk.CTkLabel(self, text=title_text, font=("Microsoft YaHei", 14, "bold"))
        self.title_label.grid(row=0, column=1, sticky="w", padx=10, pady=(10, 0))

        detail_text = f"教师: {info['courseTeacher'] or '未知'} | ID: {info['courseID']}"
        self.detail_label = ctk.CTkLabel(self, text=detail_text, font=("Microsoft YaHei", 12), text_color="gray")
        self.detail_label.grid(row=1, column=1, sticky="w", padx=10, pady=(0, 10))

        # 勾选框
        self.check_var = ctk.BooleanVar(value=True)
        self.checkbox = ctk.CTkCheckBox(self, text="", variable=self.check_var,
                                        command=lambda: on_toggle(info['courseID'], self.check_var.get()),
                                        width=20, fg_color=THEME_BLUE)
        self.checkbox.grid(row=0, column=2, rowspan=2, padx=20)


class App(ctk.CTk):
    def __init__(self):
        super().__init__()

        self.setting_widgets = None
        self.config_data = None
        self.all_courses = None
        self.title("海大抢课助手")
        self.geometry("950x680")
        self.protocol("WM_DELETE_WINDOW", self.on_closing)

        # 业务数据
        self.config_path = "config.json"
        self.courses_path = "parsedCourses.json"
        self.selected_course_ids = set()
        self.is_running = False
        self.grab_thread = None
        self.last_valid_time = ""

        # 初始化config
        self._init_config()
        # 初始化 UI
        self._setup_sidebar()
        self._setup_frames()

        # 重定向输出
        self.logger = Logger(self.log_textbox)

        # 同时重定向 标准输出 和 错误输出
        sys.stdout = self.logger
        sys.stderr = self.logger

        # 初始加载
        self.load_config()
        self.load_courses()

    def _init_config(self):
        if os.path.isfile(self.config_path):
            with open(self.config_path, "r", encoding="utf-8") as f:
                self.config_data = json.load(f)
        else:
            default_json = {
                "account": "",
                "password": "",
                "enableAutoStart": True,
                "startTime": "2026-06-23 12:00:00"
            }
            with open(self.config_path, "w", encoding="utf-8") as f:
                f.write(json.dumps(default_json, ensure_ascii=False))

    def _setup_sidebar(self):
        """侧边导航栏"""
        self.sidebar = ctk.CTkFrame(self, width=160, corner_radius=0, fg_color="#F2F2F2")
        self.sidebar.pack(side="left", fill="y")

        self.logo_label = ctk.CTkLabel(self.sidebar, text="海大抢课助手",
                                       font=("Microsoft YaHei", 20, "bold"), text_color=THEME_BLUE)
        self.logo_label.pack(pady=30)

        self.btn_home = ctk.CTkButton(self.sidebar, text="控制主页", fg_color="transparent", text_color="black",
                                      hover_color="#E0E0E0", anchor="w", command=lambda: self.show_frame("home"))
        self.btn_home.pack(fill="x", padx=10, pady=5)

        self.btn_list = ctk.CTkButton(self.sidebar, text="预选列表", fg_color="transparent", text_color="black",
                                      hover_color="#E0E0E0", anchor="w", command=lambda: self.show_frame("list"))
        self.btn_list.pack(fill="x", padx=10, pady=5)

        self.btn_setting = ctk.CTkButton(self.sidebar, text="配置设置", fg_color="transparent", text_color="black",
                                         hover_color="#E0E0E0", anchor="w", command=lambda: self.show_frame("setting"))
        self.btn_setting.pack(fill="x", padx=10, pady=5)

    def _setup_frames(self):
        """主内容区域"""
        self.container = ctk.CTkFrame(self, fg_color=BG_WHITE, corner_radius=0)
        self.container.pack(side="right", expand=True, fill="both")

        # Home Frame
        self.home_frame = ctk.CTkFrame(self.container, fg_color=BG_WHITE)

        # 顶部参数设置
        self.ctrl_card = ctk.CTkFrame(self.home_frame, fg_color=CARD_BG, corner_radius=15)
        self.ctrl_card.pack(fill="x", padx=20, pady=20)

        ctk.CTkLabel(self.ctrl_card, text="抢课策略", font=("Microsoft YaHei", 15, "bold")).grid(row=0, column=0,
                                                                                                 padx=20, pady=10,
                                                                                                 sticky="w")

        self.iter_var = ctk.StringVar(value="3")
        ctk.CTkLabel(self.ctrl_card, text="尝试轮数:").grid(row=1, column=0, padx=(20, 5), pady=10)
        self.iter_entry = ctk.CTkEntry(self.ctrl_card, textvariable=self.iter_var, width=60)
        self.iter_entry.grid(row=1, column=1, pady=10)

        self.delay_var = ctk.StringVar(value="1.0")
        ctk.CTkLabel(self.ctrl_card, text="轮次延迟(s):").grid(row=1, column=2, padx=(20, 5), pady=10)
        self.delay_entry = ctk.CTkEntry(self.ctrl_card, textvariable=self.delay_var, width=60)
        self.delay_entry.grid(row=1, column=3, pady=10)

        self.start_btn = ctk.CTkButton(self.ctrl_card, text="开始抢课", fg_color=THEME_BLUE,
                                       font=("Microsoft YaHei", 14, "bold"), height=40, command=self.toggle_grab)
        self.start_btn.grid(row=1, column=4, padx=40, pady=15)

        # 日志区
        self.log_textbox = ctk.CTkTextbox(self.home_frame, fg_color="#1E1E1E", text_color="#D4D4D4",
                                          font=("Consolas", 12), corner_radius=10)
        self.log_textbox.pack(expand=True, fill="both", padx=20, pady=(0, 20))
        self.log_textbox.configure(state="disabled")

        # List Frame
        self.list_frame = ctk.CTkFrame(self.container, fg_color=BG_WHITE)
        self.list_header = ctk.CTkFrame(self.list_frame, fg_color="transparent")
        self.list_header.pack(fill="x", padx=20, pady=(15, 10))

        # 标题
        ctk.CTkLabel(self.list_header, text="待选课程清单",
                     font=("Microsoft YaHei", 20, "bold")).pack(side="left")
        # 导入按钮
        self.import_btn = ctk.CTkButton(self.list_header, text=" 📂 导入预选课程",
                                        fg_color=THEME_BLUE,
                                        width=140, height=32,
                                        font=("Microsoft YaHei", 13),
                                        command=self.import_courses)
        self.import_btn.pack(side="right")

        # 帮助按钮
        self.help_btn = ctk.CTkButton(self.list_header, text="?",
                                      width=32, height=32, corner_radius=16,
                                      fg_color="#E0E0E0", text_color="#555555",
                                      hover_color="#D0D0D0",
                                      font=("Microsoft YaHei", 14, "bold"),
                                      command=self.show_usage_help)
        self.help_btn.pack(side="right", padx=5)

        # 滚动列表区域
        self.scroll_list = ctk.CTkScrollableFrame(self.list_frame, fg_color="transparent")
        self.scroll_list.pack(expand=True, fill="both", padx=20, pady=(0, 10))

        # Setting Frame
        self.setting_frame = ctk.CTkFrame(self.container, fg_color=BG_WHITE)
        ctk.CTkLabel(self.setting_frame, text="全局配置", font=("Microsoft YaHei", 20, "bold")).pack(pady=15, padx=20,
                                                                                                     anchor="w")

        self.settings_scroll = ctk.CTkScrollableFrame(self.setting_frame, fg_color="transparent")
        self.settings_scroll.pack(expand=True, fill="both", padx=20, pady=10)

        self.set_btn_group = ctk.CTkFrame(self.setting_frame, fg_color="transparent")
        self.set_btn_group.pack(fill="x", padx=20, pady=10)

        # 关于按钮
        self.about_btn = ctk.CTkButton(self.set_btn_group, text="关于软件",
                                       width=100,
                                       fg_color="transparent",
                                       border_width=1,
                                       border_color=THEME_BLUE,
                                       text_color=THEME_BLUE,
                                       hover_color="#E8F0FE",
                                       command=self.show_about_info)
        self.about_btn.pack(side="left", padx=10)

        # 保存设置
        self.save_btn = ctk.CTkButton(self.set_btn_group, text="保存设置",
                                      fg_color=THEME_BLUE, command=self.save_config)
        self.save_btn.pack(side="right", padx=10)

        # 重载配置
        self.reset_btn = ctk.CTkButton(self.set_btn_group, text="重载配置",
                                       fg_color="#95A5A6", command=self.load_config)
        self.reset_btn.pack(side="right", padx=10)

        self.show_frame("home")

    def show_about_info(self):
        """弹出关于信息"""
        about_msg = (
            "海大抢课助手 (HNU Course Selector)\n"
            "版本: v1.1\n"
            "最后更新: 2026-06-22\n\n"
            "--------------------------------\n"
            "作者: xlxlSakura\n"
            "核心逻辑: Python + Selenium + Requests\n"
            "界面架构: CustomTkinter\n\n"
            "本工具仅用于自动化辅助教学演示，请勿用于非法用途。"
            "因使用本软件造成的任何后果（如封号、抢课失败等）由使用者自行承担。\n"
            "--------------------------------\n"
            "© 2026 xlxlSakura. All rights reserved."
        )

        msg_box = ctk.CTkToplevel(self)
        msg_box.title("关于软件")
        msg_box.geometry("420x350")
        msg_box.attributes("-topmost", True)

        x = self.winfo_x() + (self.winfo_width() // 2) - 210
        y = self.winfo_y() + (self.winfo_height() // 2) - 175
        msg_box.geometry(f"+{x}+{y}")

        # 标题
        ctk.CTkLabel(msg_box, text="关于海大抢课助手",
                     font=("Microsoft YaHei", 18, "bold"), text_color=THEME_BLUE).pack(pady=(20, 10))

        # 内容
        text_area = ctk.CTkTextbox(msg_box, width=380, height=200, font=("Microsoft YaHei", 12))
        text_area.pack(padx=20, pady=5)
        text_area.insert("0.0", about_msg)
        text_area.configure(state="disabled")

        ctk.CTkButton(msg_box, text="确定", width=100, command=msg_box.destroy).pack(pady=15)

    def show_frame(self, name):
        self.home_frame.pack_forget()
        self.list_frame.pack_forget()
        self.setting_frame.pack_forget()

        if name == "home":
            self.home_frame.pack(expand=True, fill="both")
        elif name == "list":
            self.list_frame.pack(expand=True, fill="both")
        elif name == "setting":
            self.setting_frame.pack(expand=True, fill="both")

    def import_courses(self):
        """打开文件选择器并解析选取的html文件"""
        file_path = filedialog.askopenfilename(
            title="选取预选课程 HTML 文件",
            filetypes=[("HTML 页面", "*.html"), ("所有文件", "*.*")]
        )
        if not file_path:
            return
        try:
            print(f"正在读取并解析文件: {file_path}")

            parsed_result = getInfos.read_courses_from_html(file_path)

            if parsed_result:
                # 解析成功后，重新加载 UI 列表
                self.load_courses()
                messagebox.showinfo("导入成功", f"已成功解析并导入 {len(parsed_result)} 门课程！")
            else:
                messagebox.showwarning("解析提醒", "文件解析完成，但未发现有效课程数据。")

        except Exception as e:
            messagebox.showerror("导入失败", f"解析过程中出现错误:\n{str(e)}")
            print(f"解析错误详情: {e}")

    def load_courses(self):
        """加载解析后的课程列表"""
        for child in self.scroll_list.winfo_children():
            child.destroy()
        try:
            if not os.path.exists(self.courses_path):
                print("未找到解析后的课程文件，请先导入。")
                return

            with open(self.courses_path, "r", encoding="utf-8") as f:
                self.all_courses = json.load(f)  # 存储到实例变量供抢课逻辑使用

            # 渲染卡片
            for course in self.all_courses:
                cid = course['courseID']
                # 如果是新导入，默认都勾选
                self.selected_course_ids.add(cid)

                card = CourseCard(self.scroll_list, course, self.on_course_toggle)
                card.pack(fill="x", pady=5)

            print(f"界面已更新，加载了 {len(self.all_courses)} 门课程。")
        except Exception as e:
            print(f"加载课程失败: {e}")

    def show_usage_help(self):
        """弹出使用说明说明"""
        help_msg = (
            "💡 如何导入预选课程？\n\n"
            "1. 登录教务系统的【学生选课】页面，并进入本次选课的【预选轮次】。\n"
            "2. 点击【选课结果】按钮，会弹出一个单独的选课结果窗口。\n"
            "3. 在浏览器页面空白处【右键】 -> 【另存为】（或按键盘Ctrl + S组合键）。\n"
            "4. 保存类型选择【网页，仅 HTML】(*.html)。\n"
            "5. 回到本助手，点击右上角「导入预选课程」按钮，选择刚才保存的文件。\n\n"
            "⚠️ 注意：请勿直接保存“快捷方式”或“网页档案(mhtml)”，必须是完整的 HTML 文件。"
        )
        messagebox.showinfo("使用说明", help_msg)

    def on_course_toggle(self, cid, is_selected):
        if is_selected:
            self.selected_course_ids.add(cid)
        else:
            self.selected_course_ids.discard(cid)

    def load_config(self):
        """配置项生成"""
        for child in self.settings_scroll.winfo_children():
            child.destroy()

        try:
            with open(self.config_path, "r", encoding="utf-8") as f:
                self.config_data = json.load(f)
            self.last_valid_time = self.config_data.get("startTime", "")
            self.setting_widgets = {}

            self._create_setting_row("账号", "account", type="text")
            self._create_password_row("密码", "password")
            self._create_autostart_row("自动抢课", "enableAutoStart")
            self._create_time_row("启动时间", "startTime")

        except Exception as e:
            print(f"读取配置失败: {e}")

    def _create_setting_row(self, label_text, key, type="text"):
        row = ctk.CTkFrame(self.settings_scroll, fg_color="transparent")
        row.pack(fill="x", pady=10)

        ctk.CTkLabel(row, text=label_text, width=120, anchor="w", font=("Microsoft YaHei", 13)).pack(side="left",
                                                                                                     padx=10)

        var = ctk.StringVar(value=str(self.config_data.get(key, "")))
        entry = ctk.CTkEntry(row, textvariable=var, width=300)
        entry.pack(side="left", padx=10)

        self.setting_widgets[key] = var

    def _create_password_row(self, label_text, key):
        row = ctk.CTkFrame(self.settings_scroll, fg_color="transparent")
        row.pack(fill="x", pady=10)

        ctk.CTkLabel(row, text=label_text, width=120, anchor="w", font=("Microsoft YaHei", 13)).pack(side="left",
                                                                                                     padx=10)

        var = ctk.StringVar(value=str(self.config_data.get(key, "")))
        # 默认密文显示
        entry = ctk.CTkEntry(row, textvariable=var, width=260, show="*")
        entry.pack(side="left", padx=10)

        # 切换密码可视
        def toggle_password():
            if entry.cget("show") == "*":
                entry.configure(show="")
                eye_btn.configure(text="🔒")
            else:
                entry.configure(show="*")
                eye_btn.configure(text="👁")

        eye_btn = ctk.CTkButton(row, text="👁", width=30, fg_color="transparent",
                                text_color=THEME_BLUE, hover_color="#E0E0E0", command=toggle_password)
        eye_btn.pack(side="left")

        self.setting_widgets[key] = var

    def _create_autostart_row(self, label_text, key):
        row = ctk.CTkFrame(self.settings_scroll, fg_color="transparent")
        row.pack(fill="x", pady=10)

        ctk.CTkLabel(row, text=label_text, width=120, anchor="w", font=("Microsoft YaHei", 13)).pack(side="left",
                                                                                                     padx=10)

        var = ctk.BooleanVar(value=self.config_data.get(key, False))

        def on_toggle():
            # 如果关闭自动抢课，禁用时间输入框
            state = "normal" if var.get() else "disabled"
            self.time_entry.configure(state=state)
            if not var.get():
                self.time_entry.configure(fg_color="#F0F0F0")  # 变灰
            else:
                self.time_entry.configure(fg_color="#FFFFFF")

        switch = ctk.CTkSwitch(row, text="", variable=var, command=on_toggle, fg_color="#D1D1D1",
                               progress_color=THEME_BLUE)
        switch.pack(side="left", padx=10)

        self.setting_widgets[key] = var

    def _create_time_row(self, label_text, key):
        row = ctk.CTkFrame(self.settings_scroll, fg_color="transparent")
        row.pack(fill="x", pady=10)

        ctk.CTkLabel(row, text=label_text, width=120, anchor="w", font=("Microsoft YaHei", 13)).pack(side="left",
                                                                                                     padx=10)

        self.time_var = ctk.StringVar(value=str(self.config_data.get(key, "")))
        self.time_entry_master = row
        self.time_entry = ctk.CTkEntry(
            self.time_entry_master,
            textvariable=self.time_var,
            width=300,
            placeholder_text="格式: 2026-06-23 12:00:00"
        )
        self.time_entry.pack(side="left", padx=10)

        # 初始状态检测
        if "enableAutoStart" in self.setting_widgets:
            if not self.setting_widgets["enableAutoStart"].get():
                self.time_entry.configure(state="disabled", fg_color="#F0F0F0")

        # 绑定失去焦点事件进行校验
        self.time_entry.bind("<FocusOut>", self.validate_time_format)

        self.setting_widgets[key] = self.time_var

    def validate_time_format(self, event=None):
        """校验时间格式: yyyy-MM-dd HH:mm:ss"""
        current_val = self.time_var.get().strip()
        pattern = r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"

        is_valid = True
        if not re.match(pattern, current_val):
            is_valid = False
        else:
            try:
                datetime.strptime(current_val, "%Y-%m-%d %H:%M:%S")
            except ValueError:
                is_valid = False

        if not is_valid:
            messagebox.showwarning("格式错误",
                                   f"时间格式不正确！\n请输入: yyyy-MM-dd HH:mm:ss\n")
            self.time_var.set(self.last_valid_time)
            return False
        else:
            self.last_valid_time = current_val
            return True

    def save_config(self):
        """覆盖原有保存逻辑，增加保存前最后一次校验"""
        if self.setting_widgets["enableAutoStart"].get():
            if not self.validate_time_format():
                return

        new_config = {}
        for key, var in self.setting_widgets.items():
            val = var.get()
            if key == "enableAutoStart":
                new_config[key] = bool(val)
            else:
                new_config[key] = str(val)

        try:
            with open(self.config_path, "w", encoding="utf-8") as f:
                json.dump(new_config, f, indent=4, ensure_ascii=False)
            messagebox.showinfo("成功", "配置已成功保存！")
        except Exception as e:
            messagebox.showerror("错误", f"保存失败: {e}")

    def toggle_grab(self):
        if not self.is_running:
            self.is_running = True
            MainService.stop_flag.clear()  # 清除停止信号
            self.start_btn.configure(text="停止抢课", fg_color="#E74C3C")

            self.grab_thread = threading.Thread(target=self.run_grab_logic, daemon=True)
            self.grab_thread.start()
        else:
            self.is_running = False
            MainService.stop_flag.set()  # 发送停止信号
            self.start_btn.configure(text="正在停止...", state="disabled")
            print("\n[!] 正在发送停止信号，等待当前请求结束...")

    def run_grab_logic(self):
        """子线程抢课主逻辑代码"""
        try:
            with open(self.courses_path, "r", encoding="utf-8") as f:
                self.all_courses = json.load(f)
            active_courses = [c for c in self.all_courses if c['courseID'] in self.selected_course_ids]
            if not active_courses:
                print("错误：未选择课程")
                return
            elif not self.setting_widgets["account"].get() or not self.setting_widgets["password"].get():
                print("错误：未输入账号或密码")
                return

            start_time_str = self.setting_widgets["startTime"].get()
            MainService.wait_for_start(start_time_str)

            # 浏览器初始化
            print("正在启动浏览器...")
            MainService.safe_browser_get(MainService.main_url, "userAccount")

            print("正在自动识别验证码登录...")
            MainService.login(
                self.setting_widgets["account"].get(),
                self.setting_widgets["password"].get()
            )

            # 进入选课页面
            MainService.interruptible_sleep(1)
            MainService.enter_xsxk()

            # 执行抢课循环
            max_r = int(self.iter_var.get())
            delay_b = float(self.delay_var.get())
            MainService.batch_send_posts(active_courses, max_r, delay_b, 3.0)

        except InterruptedError:
            print("\n[✔] 抢课任务已安全停止。")
        except Exception as e:
            print(f"\n[✘] 运行出错: {e}")
        finally:
            # 无论成功、失败还是中断，都要重置按钮状态
            self.is_running = False
            self.after(0, lambda: self.start_btn.configure(text="开始抢课", fg_color=THEME_BLUE, state="normal"))
            # 关闭浏览器
            if MainService.browser:
                try:
                    MainService.browser.quit()
                except:
                    pass

    def on_closing(self):
        if MainService.browser:
            try:
                MainService.browser.quit()
            except:
                pass
        self.destroy()

if __name__ == "__main__":
    app = App()
    app.mainloop()