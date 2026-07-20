# -*- coding: utf-8 -*-
# @Time    : 2026-06-10
# @Author  : xlxlSakura
# @FileName: Utils.py
# @Software: PyCharm
# @Description: 
# @Version: 1.0

import requests
import threading

class SessionMgr:
    session = None
    lock = threading.Lock()

    @classmethod
    def get_instance(cls):
        if cls.session is None:
            with cls.lock:
                if cls.session is None:
                    cls.session = requests.Session()
                    cls.session.headers.update(                {
                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 Edg/132.0.0.0",
                    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
                    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
                    "Connection": "keep-alive",
                })
        return cls.session

    @classmethod
    def reset(cls):
        with cls.lock:
            if cls.session:
                cls.session.close()
                cls.session = None