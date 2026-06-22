# -*- coding: utf-8 -*-
# @Time    : 2026-06-10
# @Author  : xlxlSakura
# @FileName: CourseSelector.py
# @Software: PyCharm
# @Description: HNU根据预选结果自动抢课
# @Version: 1.1

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
import getInfos
import os
import json
import sys

edge_options = webdriver.EdgeOptions()
edge_options.page_load_strategy = 'normal'

user_account, user_password, courses_loc, start_time = "", "", "", ""
main_url = "http://jxgl.hainanu.edu.cn/jsxsd/"

ocr = ddddocr.DdddOcr(show_ad=False)
edge_options.add_experimental_option("detach", True)

browser = None


def init():
    global user_password, user_account, courses_loc, start_time
    base_dir = os.path.dirname(sys.executable) if getattr(sys, 'frozen', False) else os.path.dirname(
        os.path.abspath(__file__))
    with open(os.path.join(base_dir, "config.json"), "r", encoding="utf-8") as f:
        raw = f.read()
    config = json.loads(raw)
    if config:
        user_account = config["account"]
        user_password = config["password"]
        start_time = config.get("startTime", "")
        pre_pick = config["prePickCoursesLoc"]
        if pre_pick != "":
            courses_loc = pre_pick
            parsed_courses = getInfos.do_parse(0, courses_loc)
        else:
            parsed_courses = getInfos.do_parse(1, courses_loc)
        return parsed_courses
    else:
        return None


def wait_for_start(target_time_str):
    if not target_time_str:
        print("未设置开始时间，将直接启动。")
        return

    target_time = datetime.strptime(target_time_str, "%Y-%m-%d %H:%M:%S")
    print(f"预设启动时间为: {target_time_str}")

    while True:
        now = datetime.now()
        if now >= target_time:
            print(f"时间已到 ({now})，开始启动程序...")
            break

        diff = (target_time - now).total_seconds()
        if diff > 10:
            print(f"距离抢课还有 {int(diff)} 秒...", end='\r')
            time.sleep(1)
        else:
            # 最后10秒进入高频检测
            time.sleep(0.1)


def safe_browser_get(url, check_element_id):
    global browser
    if browser is None:
        browser = webdriver.Edge(options=edge_options)

    while True:
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
        try:
            if "xsMain" in browser.current_url:
                browser.get(main_url + "xsxk/xklc_list")
            time.sleep(1)
            WebDriverWait(browser, 5).until(
                EC.element_to_be_clickable((By.XPATH, "//span[contains(text(), '进入选课')]"))
            ).click()
            break
        except:
            print("进入选课列表失败，重试中...")
            browser.refresh()
            time.sleep(1)


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


def batch_send_posts(courses):
    """
    遍历课程 ID 列表并发送请求，带随机延迟
    """
    session = Utils.SessionMgr.get_instance()
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
    current_queue = courses
    attempt_round = 1
    max_rounds = 5
    while current_queue and attempt_round <= max_rounds:
        print(f"\n--- 第 {attempt_round} 轮选课开始，剩余 {len(current_queue)} 门 ---")
        failed_list = []

        for index, course_data in enumerate(current_queue):
            print(f"正在处理第 {index + 1}/{len(current_queue)} 个课程: {course_data.get('courseName')}")
            success, message = send_post(session, course_data)

            if not success:
                failed_list.append(course_data)

            if index < len(current_queue) - 1:
                wait_time = random.uniform(0.7, 1.1)
                time.sleep(wait_time)

        current_queue = failed_list
        if current_queue:
            print(f"\n第 {attempt_round} 轮结束，有 {len(current_queue)} 门课失败。")
            if attempt_round < max_rounds:
                delay_between_rounds = 5
                time.sleep(delay_between_rounds)
        else:
            print("\n恭喜！所有预定课程已处理完毕。")

        attempt_round += 1


if __name__ == '__main__':
    courses = init()
    print("已读取到抢课课表，共",len(courses),"门课程。")

    wait_for_start(start_time)

    safe_browser_get(main_url, "userAccount")

    login(user_account, user_password)
    time.sleep(1)
    enter_xsxk()
    time.sleep(1)
    batch_send_posts(courses)