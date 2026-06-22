from bs4 import BeautifulSoup
import re
import json
import os
import sys

def parse_course_html(html):
    soup = BeautifulSoup(html, 'html.parser')
    course_list = []

    # 找到表格的 tbody 部分，遍历每一行 tr
    rows = soup.find('tbody').find_all('tr')

    for row in rows:
        # 获取该行所有的单元格 td
        cells = row.find_all('td')

        # 如果单元格数量太少（可能是空行），跳过
        if len(cells) < 10:
            continue

        # 课程号 (第1个 td)
        course_num = cells[0].get_text(strip=True)

        # 课程名 (第2个 td)
        course_name = cells[1].get_text(strip=True)

        # 任课教师 (第6个 td)
        course_teacher = cells[5].get_text(strip=True)

        # 格式：javascript:xstkOper('202620271019189');
        course_id = ""
        op_link = cells[-1].find('a', href=re.compile(r'xstkOper'))
        if op_link:
            href_value = op_link['href']
            match = re.search(r"xstkOper\('(\d+)'\)", href_value)
            if match:
                course_id = match.group(1)

        course_info = {
            "courseName": course_name,
            "courseNum": course_num,
            "courseTeacher": course_teacher,
            "courseID": course_id
        }

        course_list.append(course_info)

    return course_list

def do_parse(mode, file_dir):
    base_dir = os.path.dirname(sys.executable) if getattr(sys, 'frozen', False) else os.path.dirname(os.path.abspath(__file__))
    if mode == 0:
        with open(file_dir, "r", encoding="utf-8") as f:
            content = f.read()
        result = parse_course_html(content)
        print(result)
        try:
            with open(os.path.join(base_dir,"parsedCourses.json"), 'w', encoding='utf-8') as f:
                json.dump(result, f, indent=4, ensure_ascii=False)
            print("成功！数据已保存")
        except Exception as e:
            print(f"保存失败: {e}")
        return result
    else:
        with open(os.path.join(base_dir,"parsedCourses.json"), 'r', encoding='utf-8') as f:
            data = json.load(f)
        return list(data)
