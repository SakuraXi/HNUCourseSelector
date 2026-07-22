# -*- coding: utf-8 -*-
# @Time    : 2026-07-21
# @Author  : xlxlSakura
# @FileName: MainService.py
# @Software: PyCharm
# @Description: 抢课助手主程序
# @Version: 1.0

import threading

import random
import ddddocr
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
import time
from datetime import datetime
from PIL import Image
from io import BytesIO
import Utils

edge_options = webdriver.EdgeOptions()
edge_options.page_load_strategy = 'normal'

main_url = "http://jxgl.hainanu.edu.cn/jsxsd/"

ocr = ddddocr.DdddOcr(show_ad=False)
edge_options.add_experimental_option("detach", True)

browser = None

stop_flag = threading.Event()

def check_continue():
    """检查是否继续运行，如果停止则抛出异常中断逻辑"""
    if stop_flag.is_set():
        raise InterruptedError("用户终止了程序")


def interruptible_sleep(seconds):
    """可中断的睡眠：每0.1秒检查一次停止信号"""
    start_time = time.time()
    while time.time() - start_time < seconds:
        if stop_flag.is_set():
            raise InterruptedError("用户终止了程序")
        time.sleep(0.1)

def safe_browser_get(url, check_element_id):
    global browser
    browser = webdriver.Edge(options=edge_options)

    while True:
        check_continue()
        try:
            print(f"正在尝试访问: {url}")
            browser.get(url)
            #检查登录框是否存在，证明页面加载成功
            WebDriverWait(browser, 5).until(
                EC.presence_of_element_located((By.ID, check_element_id))
            )
            print("页面加载成功！")
            break
        except Exception as e:
            print(f"访问失败或服务器无响应，正在重试... (Error: {e})")
            time.sleep(0.3)

def login(uname, password):
    unameE = browser.find_element(By.ID, "userAccount")
    pwdE = browser.find_element(By.ID, "userPassword")
    codeimgE = browser.find_element(By.ID, "SafeCodeImg")
    codeE = browser.find_element(By.ID, "RANDOMCODE")
    unameE.send_keys(uname)
    pwdE.send_keys(password)

    try:
        image = Image.open(BytesIO(codeimgE.screenshot_as_png))
    except Exception as e:
        print(f"Can not open image file: {e}")
        return None
    res = ocr.classification(image)
    print(f"验证码识别结果: {res}")
    codeE.send_keys(res)

    login_btn = browser.find_element(By.ID, "btn-login")
    login_btn.click()

def enter_xsxk():
    """
    进入选课section
    """
    while True:
        check_continue()
        try:
            if "xsMain" in browser.current_url:
                browser.get(main_url + "xsxk/xklc_list")
            if "xsrkxz" in browser.current_url:
                link_element = WebDriverWait(browser, 10).until(EC.presence_of_element_located((By.CSS_SELECTOR, "#dataList td a")))
                target_url = link_element.get_attribute("href")
                print(f"选课轮次链接: {target_url}")
                browser.get(target_url)

            interruptible_sleep(1)
            WebDriverWait(browser, 5).until(
                EC.element_to_be_clickable((By.XPATH, "//span[contains(text(), '进入选课')]"))
            ).click()
            break
        except:
            print("进入选课列表失败，重试中...")
            browser.refresh()
            interruptible_sleep(1)

def send_post(session, course_data):
    """
    发送选课请求
    返回: (bool, str) -> (是否成功, 服务器返回的消息)
    """
    course_id = course_data.get("courseID")
    course_name = course_data.get("courseName")

    params = {
        "kcid": "",
        "cfbs": "null",
        "jx0404id": str(course_id),
        "xkzy": "",
        "trjf": ""
    }
    try:
        response = session.post(
            "https://jxgl.hainanu.edu.cn/jsxsd/xsxkkc/bxxkOper",
            params=params,
            timeout=10
        )
        print(response.text)
        try:
            res_json = response.json()
            msg = res_json.get("message", "")
        except:
            msg = response.text

        if "成功" in msg:
            print(f"✅ 【{course_name}】选课成功！")
            return True, msg
        else:
            print(f"❌ 【{course_name}】失败: {msg}")
            return False, msg
    except Exception as e:
        print(f"【{course_name}】请求发生异常: {e}")
        return False, str(e)

def wait_for_start(target_time_str):
    if not target_time_str: return
    target_time = datetime.strptime(target_time_str, "%Y-%m-%d %H:%M:%S")
    print(f"等待启动时间: {target_time_str}")

    while datetime.now() < target_time:
        check_continue()  # 检查停止信号
        diff = (target_time - datetime.now()).total_seconds()
        print(f"距离开始还有 {int(diff)} 秒...", end='\r')
        time.sleep(0.5)


def batch_send_posts(courses, max_rounds, delay_base, rounds_delay):
    session = Utils.SessionMgr.get_instance()
    # 同步浏览器 Cookie
    selenium_cookies = browser.get_cookies()
    for cookie in selenium_cookies:
        session.cookies.set(cookie['name'], cookie['value'])

    user_agent = browser.execute_script("return navigator.userAgent")
    session.headers.update({"User-Agent": user_agent})
    session.headers.update({
        "Referer": browser.current_url,
        "X-Requested-With": "XMLHttpRequest",
        "Content-Type": "application/x-www-form-urlencoded"
    })
    attempt_round = 1
    current_queue = courses
    while current_queue and attempt_round <= max_rounds:
        check_continue()
        print(f"\n--- 第 {attempt_round} 轮选课开始，剩余 {len(current_queue)} 门 ---")

        failed_list = []
        for course_data in current_queue:
            check_continue()
            success, msg = send_post(session, course_data)
            if not success:
                failed_list.append(course_data)

            # 课程间的随机延迟
            interruptible_sleep(random.uniform(delay_base * 0.8, delay_base * 1.2))

        current_queue = failed_list

        if current_queue:
            print(f"\n第 {attempt_round} 轮结束，有 {len(current_queue)} 门课失败。")
            if attempt_round < max_rounds:
                interruptible_sleep(random.uniform(rounds_delay * 0.8, rounds_delay * 1.2))
        else:
            print("\n恭喜！所有预定课程已处理完毕。")
            break

        attempt_round += 1