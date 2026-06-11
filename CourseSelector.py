# -*- coding: utf-8 -*-
# @Time    : 2026-06-10
# @Author  : xlxlSakura
# @FileName: CourseSelector.py
# @Software: PyCharm
# @Description: HNU根据预选结果自动抢课
# @Version: 1.0

import random
import ddddocr
from selenium import webdriver
from selenium.webdriver.common.by import By
import time
from PIL import Image
from io import BytesIO
import Utils
import getInfos
import os
import json
import sys

edge_options = webdriver.EdgeOptions()
user_account,user_password,courses_loc = "","",""
main_url = "http://jxgl.hainanu.edu.cn/jsxsd/"

ocr = ddddocr.DdddOcr(show_ad=False)

edge_options.add_experimental_option("detach", True)

browser = webdriver.Edge(options=edge_options)

def init():
    global user_password, user_account, mode, courses_loc
    base_dir = os.path.dirname(sys.executable) if getattr(sys, 'frozen', False) else os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(base_dir,"config.json"), "r", encoding="utf-8") as f:
        raw = f.read()
    config = json.loads(raw)
    if config:
        user_account = config["account"]
        user_password = config["password"]
        pre_pick = config["prePickCoursesLoc"]
        if pre_pick != "":
            courses_loc = pre_pick
            return getInfos.do_parse(0, courses_loc)
        return getInfos.do_parse(1, courses_loc)
    else :
        return None


def login(uname,password):
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
    print(res)
    codeE.send_keys(res)

    login_btn = browser.find_element(By.ID, "btn-login")
    login_btn.click()

def enter_xsxk():
    browser.get(main_url + "xsxk/xklc_list")
    time.sleep(2)
    browser.find_element(By.XPATH, "//span[contains(text(), '进入选课')]").click()

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
        # 使用传入的 session 发送
        response = session.post(
            "https://jxgl.hainanu.edu.cn/jsxsd/xsxkkc/bxxkOper",
            params=params,
            timeout=10
        )
        try:
            res_json = response.json()
            status = str(res_json.get("success", ""))
            msg = res_json.get("message", "")
        except:
            status = "false"
            msg = response.text

        if status == "true":
            print(f"✅ 【{course_name}】选课成功！")
            return True, msg
        else:
            print(f"❌ 【{course_name}】失败: {msg}")
            return False, msg
    except Exception as e:
        print(f"【{course_name}】请求发生异常: {e}")

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
    max_rounds = 3 # 设置最大重试轮数，避免死循环
    while current_queue and attempt_round <= max_rounds:
        print(f"\n--- 第 {attempt_round} 轮选课开始，剩余 {len(current_queue)} 门 ---")
        failed_list = []

        for index, course_data in enumerate(current_queue):
            print(f"正在处理第 {index + 1}/{len(courses)} 个课程: {course_data.get("courseName")}")
            success, message = send_post(session, course_data)

            if not success:
                failed_list.append(course_data)

            # Jitter 延迟
            if index < len(current_queue) - 1:
                wait_time = 1.0 + random.uniform(1.0, 2.0)
                print(f"等待 {wait_time:.2f} 秒后进行下一次请求...")
                time.sleep(wait_time)

        # 更新队列为失败的列表
        current_queue = failed_list

        if current_queue:
            print(f"\n第 {attempt_round} 轮结束，有 {len(current_queue)} 门课失败。")
            if attempt_round < max_rounds:
                delay_between_rounds = 10  # 轮与轮之间delay
                print(f"{delay_between_rounds} 秒后开始下一轮重试...")
                time.sleep(delay_between_rounds)
        else:
            print("\n恭喜！所有预定课程已处理完毕。")

        attempt_round += 1

    if current_queue:
        print(f"\n任务结束。仍有 {len(current_queue)} 门课程未选上，以下为失败课程：")
        print(current_queue)

if __name__ == '__main__':
    courses = init()
    browser.get(main_url)
    login(user_account,user_password)
    time.sleep(random.uniform(1.0, 2.0))
    enter_xsxk()
    time.sleep(random.uniform(1.0, 2.0))
    batch_send_posts(courses)